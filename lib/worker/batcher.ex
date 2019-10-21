require Logger

defmodule BorsNG.Worker.Batcher do
  @moduledoc """
  A "Batcher" manages the backlog of batches a project has.
  It implements this set of rules:

    * When a patch is reviewed ("r+'ed"),
      it gets added to the project's non-running batch.
      If no such batch exists, it creates it.
    * After a short delay, if there is no currently running batch,
      the project's non-running batch is started.
    * The project's CI is occasionally polled,
      if a batch is currently running.
      After polling, the completion logic is run.
    * If a notification related to the underlying CI is received,
      the completion logic is run.
    * When the completion logic is run, the batch is either
      bisected (if it failed and there are two or more patches in it),
      blocked (if it failed and there is only one patch in it),
      pushed to master (if it passed),
      or (if there are still CI jobs with no results) it is left alone.
  """

  use GenServer
  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Batch
  alias BorsNG.Database.BatchState
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Status
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.GitHub
  alias BorsNG.Endpoint
  import BorsNG.Router.Helpers
  import Ecto.Query

  # Every half-hour
  @poll_period 30 * 60 * 1000

  # Public API

  def start_link(project_id) do
    GenServer.start_link(__MODULE__, project_id)
  end

  def reviewed(pid, patch_id, reviewer) when is_integer(patch_id) do
    GenServer.cast(pid, {:reviewed, patch_id, reviewer})
  end

  def set_priority(pid, patch_id, priority) when is_integer(patch_id) do
    GenServer.call(pid, {:set_priority, patch_id, priority})
  end

  def status(pid, stat) do
    GenServer.cast(pid, {:status, stat})
  end

  def poll(pid) do
    send(pid, {:poll, :once})
  end

  def cancel(pid, patch_id) when is_integer(patch_id) do
    GenServer.cast(pid, {:cancel, patch_id})
  end

  def cancel_all(pid) do
    GenServer.cast(pid, {:cancel_all})
  end

  # Server callbacks

  def init(project_id) do
    Process.send_after(
      self(),
      {:poll, :repeat},
      trunc(@poll_period * :rand.uniform(2) * 0.5))
    {:ok, project_id}
  end

  def handle_cast(args, project_id) do
    do_handle_cast(args, project_id)
    {:noreply, project_id}
  end

  def handle_call({:set_priority, patch_id, priority}, _from, project_id) do
    case Repo.get(Patch, patch_id) do
      nil -> nil
      %{priority: ^priority} -> nil
      patch ->
        patch.id
        |> Batch.all_for_patch(:incomplete)
        |> Repo.one()
        |> raise_batch_priority(priority)
        patch
        |> Patch.changeset(%{priority: priority})
        |> Repo.update!()
    end

    {:reply, :ok, project_id}
  end

  def do_handle_cast({:reviewed, patch_id, reviewer}, project_id) do
    case Repo.get(Patch.all(:awaiting_review), patch_id) do
      nil ->
        # Patch exists (otherwise, no ID), but is not awaiting review
        patch = Repo.get!(Patch, patch_id)
        project = Repo.get!(Project, patch.project_id)
        project
        |> get_repo_conn()
        |> send_message([patch], :already_running_review)
      patch ->
        # Patch exists and is awaiting review
        # This will cause the PR to start after the patch's scheduled delay
        project = Repo.get!(Project, patch.project_id)
        repo_conn = get_repo_conn(project)
        case patch_preflight(repo_conn, patch) do
          :ok ->
            {batch, is_new_batch} = get_new_batch(
              project_id,
              patch.into_branch,
              patch.priority
            )
            %LinkPatchBatch{}
            |> LinkPatchBatch.changeset(%{
              batch_id: batch.id,
              patch_id: patch.id,
              reviewer: reviewer})
            |> Repo.insert!()
            if is_new_batch do
              put_incomplete_on_hold(get_repo_conn(project), batch)
            end
            poll_after_delay(project)
            send_status(repo_conn, batch.id, [patch], :waiting)
          {:error, message} ->
            send_message(repo_conn, [patch], {:preflight, message})
        end
    end
  end

  def do_handle_cast({:status, {commit, identifier, state, url}}, project_id) do
    project_id
    |> Batch.get_assoc_by_commit(commit)
    |> Repo.all()
    |> case do
      [batch] ->
        batch.id
        |> Status.get_for_batch(identifier)
        |> Repo.update_all([set: [state: state, url: url, identifier: identifier]])
        if batch.state == :running do
          maybe_complete_batch(batch)
        end
      [] -> :ok
    end
  end

  def do_handle_cast({:cancel, patch_id}, _project_id) do
    patch_id
    |> Batch.all_for_patch(:incomplete)
    |> Repo.one()
    |> cancel_patch(patch_id)
  end

  def do_handle_cast({:cancel_all}, project_id) do
    waiting = project_id
    |> Batch.all_for_project(:waiting)
    |> Repo.all()
    Enum.each(waiting, &Repo.delete!/1)
    running = project_id
    |> Batch.all_for_project(:running)
    |> Repo.all()
    Enum.map(running, &Batch.changeset(&1, %{state: :canceled}))
    |> Enum.each(&Repo.update!/1)
    repo_conn = Project
    |> Repo.get!(project_id)
    |> get_repo_conn()
    Enum.each(running, &send_status(repo_conn, &1, :canceled))
    Enum.each(waiting, &send_status(repo_conn, &1, :canceled))
  end

  def handle_info({:poll, repetition}, project_id) do
    if repetition != :once do
      Process.send_after(self(), {:poll, repetition}, @poll_period)
    end
    case poll_(project_id) do
      :stop ->
        {:stop, :normal, project_id}
      :again ->
        {:noreply, project_id}
    end
  end

  # Private implementation details

  defp poll_(project_id) do
    project = Repo.get(Project, project_id)
    incomplete = project_id
    |> Batch.all_for_project(:incomplete)
    |> Repo.all()
    incomplete
    |> Enum.map(&%Batch{&1 | project: project})
    |> sort_batches()
    |> poll_batches()
    if Enum.empty?(incomplete) do
      :stop
    else
      :again
    end
  end

  def sort_batches(batches) do
    sorted_batches = Enum.sort_by(batches, &{
      -BatchState.numberize(&1.state),
      -&1.priority,
      &1.last_polled
    })
    new_batches = Enum.dedup_by(sorted_batches, &(&1.id))
    state = if new_batches != [] and hd(new_batches).state == :running do
      :running
    else
      Enum.each(new_batches, fn batch -> :waiting =  batch.state end)
      :waiting
    end
    {state, new_batches}
  end

  defp poll_batches({:waiting, batches}) do
    case Enum.filter(batches, &Batch.next_poll_is_past/1) do
      [] -> :ok
      [batch | _] -> start_waiting_batch(batch)
    end
  end

  defp poll_batches({:running, batches}) do
    batch = hd(batches)
    cond do
      Batch.timeout_is_past(batch) ->
        timeout_batch(batch)
      Batch.next_poll_is_past(batch) ->
        poll_running_batch(batch)
      true -> :ok
    end
  end

  defp start_waiting_batch(batch) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    patch_links = Repo.all(LinkPatchBatch.from_batch(batch.id))
    |> Enum.sort_by(&(&1.patch.pr_xref))
    stmp = "#{project.staging_branch}.tmp"

    base = GitHub.get_branch!(
      repo_conn,
      batch.into_branch)
    tbase = %{
      tree: base.tree,
      commit: GitHub.synthesize_commit!(
        repo_conn,
        %{
          branch: stmp,
          tree: base.tree,
          parents: [base.commit],
          commit_message: "[ci skip][skip ci][skip netlify]",
          committer: nil})}
    do_merge_patch = fn %{patch: patch}, branch ->
      case branch do
        :conflict -> :conflict
        :canceled -> :canceled
        _ -> GitHub.merge_branch!(
          repo_conn,
          %{
            from: patch.commit,
            to: stmp,
            commit_message: "[ci skip][skip ci][skip netlify] -bors-staging-tmp-#{patch.pr_xref}"})
      end
    end

    merge = Enum.reduce(patch_links, tbase, do_merge_patch)
    {status, commit} = start_waiting_merged_batch(
      batch,
      patch_links,
      base,
      merge)
    now = DateTime.to_unix(DateTime.utc_now(), :second)

    GitHub.delete_branch!(repo_conn, stmp)
    send_status(repo_conn, batch, status)
    batch
    |> Batch.changeset(%{state: status, commit: commit, last_polled: now})
    |> Repo.update!()

    Project.ping!(batch.project_id)
    status
  end

  defp start_waiting_merged_batch(_batch, [], _, _) do
    {:canceled, nil}
  end

  defp start_waiting_merged_batch(batch, patch_links, base, %{tree: tree}) do
    repo_conn = get_repo_conn(batch.project)
    patches = Enum.map(patch_links, &(&1.patch))

    repo_conn
    |> Batcher.GetBorsToml.get("#{batch.project.staging_branch}.tmp")
    |> case do
      {:ok, toml} ->
        parents = if toml.use_squash_merge do
          stmp = "#{batch.project.staging_branch}.tmp2"
          GitHub.force_push!(repo_conn, base.commit, stmp)

          new_head = Enum.reduce(patch_links, base.commit, fn patch_link, prev_head ->

            Logger.debug("Patch Link #{inspect(patch_link)}")
            Logger.debug("Patch #{inspect(patch_link.patch)}")

            {:ok, commits} = GitHub.get_pr_commits(repo_conn, patch_link.patch.pr_xref)
            {:ok, pr} = GitHub.get_pr(repo_conn, patch_link.patch.pr_xref)

            {token, _} = repo_conn
             user = GitHub.get_user_by_login!(token, pr.user.login)

            Logger.debug("PR #{inspect(pr)}")
            Logger.debug("User #{inspect(user)}")

            # If a user doesn't have a public email address in their GH profile
            # then get the email from the first commit to the PR
            user_email = if user.email != nil do
              user.email
            else
              Enum.at(commits, 0).author_email
            end

            # The head sha is the final commit in the PR.
            source_sha =  pr.head_sha
            Logger.info("Staging branch #{stmp}")
            Logger.info("Commit sha #{source_sha}")

            # Create a merge commit for each PR
            # because each PR is merged on top of each other in stmp, we can verify against any merge conflicts
            merge_commit = GitHub.merge_branch!(repo_conn,
               %{
               from: source_sha,
               to: stmp,
                 commit_message: "[ci skip][skip ci][skip netlify] -bors-staging-tmp-#{source_sha}"}
            )

            Logger.info("Merge Commit #{inspect(merge_commit)}")

            Logger.info("Previous Head #{inspect(prev_head)}")
            # Then compress the merge commit into tree into a single commit
            # appent it to the previous commit
            # Because the merges are iterative the contain *only* the changes from the PR vs the previous PR(or head)
            cpt = GitHub.create_commit!(
              repo_conn,
              %{
                tree: merge_commit.tree,
                parents: [prev_head],
                commit_message: "#{pr.title} (##{pr.number})\n\n#{pr.body}",
                committer: %{name: user.login, email: user_email}})

            Logger.info("Commit Sha #{inspect(cpt)}")
              cpt

          end)
          GitHub.delete_branch!(repo_conn, stmp)
          [new_head]
        else
          parents = [base.commit | Enum.map(patch_links, &(&1.patch.commit))]
          parents
        end

        head = if toml.use_squash_merge do
          # This will avoid creating a merge commit, which is important since it will prevent
          # bors from polluting th git blame history with it's own name
            head = Enum.at(parents, 0)
            GitHub.force_push!(repo_conn, head, batch.project.staging_branch)
            head
        else
          commit_message = Batcher.Message.generate_commit_message(
            patch_links,
            toml.cut_body_after,
            gather_co_authors(batch, patch_links))
          GitHub.synthesize_commit!(
            repo_conn,
            %{
              branch: batch.project.staging_branch,
              tree: tree,
              parents: parents,
              commit_message: commit_message,
              committer: toml.committer})
        end

        setup_statuses(batch, toml)
        {:running, head}
      {:error, message} ->
        message = Batcher.Message.generate_bors_toml_error(message)
        send_message(repo_conn, patches, {:config, message})
        {:error, nil}
    end
  end

  defp start_waiting_merged_batch(batch, patch_links, _base, :conflict) do
    repo_conn = get_repo_conn(batch.project)
    patches = Enum.map(patch_links, &(&1.patch))
    state = bisect(patch_links, batch)
    send_message(repo_conn, patches, {:conflict, state})
    {:conflict, nil}
  end

  def gather_co_authors(batch, patch_links) do
    repo_conn = get_repo_conn(batch.project)
    patch_links
    |> Enum.map(&(&1.patch.pr_xref))
    |> Enum.flat_map(&GitHub.get_pr_commits!(repo_conn, &1))
    |> Enum.map(&("#{&1.author_name} <#{&1.author_email}>"))
    |> Enum.uniq
  end

  defp setup_statuses(batch, toml) do
    toml.status
    |> Enum.map(&%Status{
        batch_id: batch.id,
        identifier: &1,
        url: nil,
        state: :running})
    |> Enum.each(&Repo.insert!/1)
    now = DateTime.to_unix(DateTime.utc_now(), :second)
    batch
    |> Batch.changeset(%{timeout_at: now + toml.timeout_sec})
    |> Repo.update!()
  end

  defp poll_running_batch(batch) do
    batch.project
    |> get_repo_conn()
    |> GitHub.get_commit_status!(batch.commit)
    |> Enum.each(fn {identifier, state} ->
      batch.id
      |> Status.get_for_batch(identifier)
      |> Repo.update_all([set: [state: state, identifier: identifier]])
    end)
    maybe_complete_batch(batch)
  end

  defp maybe_complete_batch(batch) do
    statuses = Repo.all(Status.all_for_batch(batch.id))
    status = Batcher.State.summary_database_statuses(statuses)
    now = DateTime.to_unix(DateTime.utc_now(), :second)
    if status != :running do
      batch.project
      |> get_repo_conn()
      |> send_status(batch, status)
      Project.ping!(batch.project_id)
      complete_batch(status, batch, statuses)
    end
    batch
    |> Batch.changeset(%{state: status, last_polled: now})
    |> Repo.update!()
    if status != :running do
      poll_(batch.project_id)
    end
  end

  @spec complete_batch(Status.state, Batch.t, [Status.t]) :: :ok
  defp complete_batch(:ok, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    {res,toml} = case Batcher.GetBorsToml.get(repo_conn, "#{batch.project.staging_branch}") do
      {:error, :fetch_failed} -> Batcher.GetBorsToml.get(repo_conn, "#{batch.project.staging_branch}.tmp")
      {:ok, x} -> {:ok, x}
    end

    {:ok, _} = push_with_retry(
      repo_conn,
      batch.commit,
      batch.into_branch)

    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()

    if toml.use_squash_merge do
      Enum.each(patches, fn patch ->
        pr = GitHub.get_pr!(repo_conn, patch.pr_xref)
        pr = %BorsNG.GitHub.Pr{pr | state: :closed, title: "[Merged by Bors] - #{pr.title}"}
        pr = GitHub.update_pr!(repo_conn, pr)
        GitHub.post_comment!(repo_conn, patch.pr_xref, "# Pull request successfully merged into master.")
      end)
    end

    send_message(repo_conn, patches, {:succeeded, statuses})
  end

  defp complete_batch(:error, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    erred = Enum.filter(statuses, &(&1.state == :error))
    patch_links = batch.id
    |> LinkPatchBatch.from_batch()
    |> Repo.all()
    patches = Enum.map(patch_links, &(&1.patch))
    state = bisect(patch_links, batch)
    send_message(repo_conn, patches, {state, erred})
  end

  # A delay has been observed between Bors sending the Status change
  # and GitHub allowing a Status-bearing commit to be pushed to master.
  # As a workaround, retry with exponential backoff.
  # This should retry *nine times*, by the way.
  defp push_with_retry(repo_conn, commit, into_branch, timeout \\ 1) do
    Process.sleep(timeout)
    result = GitHub.push(
      repo_conn,
      commit,
      into_branch)
    case result do
      {:ok, _} -> result
      _ when timeout >= 512 -> result
      _ -> push_with_retry(repo_conn, commit, into_branch, timeout * 2)
    end
  end

  defp timeout_batch(batch) do
    project = batch.project
    patch_links = batch.id
    |> LinkPatchBatch.from_batch()
    |> Repo.all()
    patches = Enum.map(patch_links, &(&1.patch))
    state = bisect(patch_links, batch)
    project
    |> get_repo_conn()
    |> send_message(patches, {:timeout, state})
    batch
    |> Batch.changeset(%{state: :error})
    |> Repo.update!()
    Project.ping!(project.id)
    project
    |> get_repo_conn()
    |> send_status(batch, :timeout)
  end

  defp cancel_patch(nil, _), do: :ok

  defp cancel_patch(batch, patch_id) do
    cancel_patch(batch, patch_id, batch.state)
    Project.ping!(batch.project_id)
  end

  defp cancel_patch(batch, patch_id, :running) do
    project = batch.project
    patch_links = batch.id
    |> LinkPatchBatch.from_batch()
    |> Repo.all()
    patches = Enum.map(patch_links, &(&1.patch))
    state = case tl(patch_links) do
      [] -> :failed
      _ -> :retrying
    end
    batch
    |> Batch.changeset(%{state: :canceled})
    |> Repo.update!()
    repo_conn = get_repo_conn(project)
    if state == :retrying do
      uncanceled_patch_links = Enum.filter(
        patch_links,
        &(&1.patch_id != patch_id))
      clone_batch(uncanceled_patch_links, project.id, batch.into_branch)
      canceled_patches = Enum.filter(
        patches,
        &(&1.id == patch_id))
      uncanceled_patches = Enum.filter(
        patches,
        &(&1.id != patch_id))
      send_message(repo_conn, canceled_patches, {:canceled, :failed})
      send_message(repo_conn, uncanceled_patches, {:canceled, :retrying})
    else
      send_message(repo_conn, patches, {:canceled, :failed})
    end
    send_status(repo_conn, batch, :canceled)
  end

  defp cancel_patch(batch, patch_id, _state) do
    project = batch.project
    LinkPatchBatch
    |> Repo.get_by!(batch_id: batch.id, patch_id: patch_id)
    |> Repo.delete!()
    if Batch.is_empty(batch.id, Repo) do
      Repo.delete!(batch)
    end
    patch = Repo.get!(Patch, patch_id)
    repo_conn = get_repo_conn(project)
    send_status(repo_conn, batch.id, [patch], :canceled)
    send_message(repo_conn, [patch], {:canceled, :failed})
  end

  defp bisect(patch_links, %Batch{project: project, into_branch: into}) do
    count = Enum.count(patch_links)
    if count > 1 do
      {lo, hi} = Enum.split(patch_links, div(count, 2))
      clone_batch(lo, project.id, into)
      clone_batch(hi, project.id, into)
      poll_after_delay(project)
      :retrying
    else
      :failed
    end
  end

  defp patch_preflight(repo_conn, patch) do
    if Patch.ci_skip?(patch) do
      {:error, :ci_skip}
    else
      toml = Batcher.GetBorsToml.get(
        repo_conn,
        patch.commit)
      patch_preflight(repo_conn, patch, toml)
    end
  end

  defp patch_preflight(_repo_conn, _patch, {:error, _}) do
    :ok
  end

  defp check_code_owner(repo_conn, patch, toml) do

    if !toml.use_codeowners do
      true
    else

      Logger.info("Checking code owners")
      {:ok, code_owner} = Batcher.GetCodeOwners.get(repo_conn, "master")
      Logger.info("CODEOWNERS file #{inspect(code_owner)}")


      {:ok, files} = GitHub.get_pr_files(repo_conn, patch.pr_xref)
      Logger.info("Files found: #{inspect(files)}")


      required_reviews = BorsNG.CodeOwnerParser.list_required_reviews(code_owner, files)

      passed_review = repo_conn
                      |> GitHub.get_reviews!(patch.pr_xref)

      Logger.info("Passed reviews: #{inspect(passed_review)}")

      # Convert the list of required reviewers into a list of true/false
      # true indicates that the reviewers requirement was satisfied,
      # false if it is open
      approved_reviews = Enum.map(required_reviews, fn x ->

        # Convert a list of OR reviewers into a true or false
        Enum.any?(x, fn required ->
          if String.contains?(required, "/") do
            # Remove leading @ for team name
            # Split into org name and team name
            team_split = String.slice(required, 1, String.length(required)-1)
                         |> String.split("/")

            # Lookup team ID -> needed later
            {:ok, team} = GitHub.get_team_by_name(repo_conn, Enum.at(team_split, 0), Enum.at(team_split, 1))

            Logger.info("Team: #{inspect(team)}")

            # Loop through reviewers, if they on the team accept their approval
            team_approved = Enum.any?(passed_review["approvers"], fn x ->
                GitHub.belongs_to_team?(repo_conn, x, team.id)
            end)

            Logger.info("Approved: #{inspect(team_approved)}")
            team_approved
          end
        end)
      end)

      code_owner_approval = Enum.reduce(approved_reviews, true, fn x,acc -> x && acc  end)

      Logger.info("Approved reviews: #{inspect(approved_reviews)}")
      Logger.info("Code Owner approval: #{inspect(code_owner_approval)}")

      code_owner_approval
    end

  end


  defp patch_preflight(repo_conn, patch, {:ok, toml}) do
    passed_label = repo_conn
    |> GitHub.get_labels!(patch.pr_xref)
    |> MapSet.new()
    |> MapSet.disjoint?(MapSet.new(toml.block_labels))
    passed_status = repo_conn
    |> GitHub.get_commit_status!(patch.commit)
    |> Enum.filter(fn {_, status} -> status != :ok end)
    |> Enum.map(fn {context, _} -> context end)
    |> MapSet.new()
    |> MapSet.disjoint?(MapSet.new(toml.pr_status))

    code_owners_approved = check_code_owner(repo_conn, patch, toml)

#    {:error, {:missing_code_owner_approval, "My team"}}

    passed_review = repo_conn
    |> GitHub.get_reviews!(patch.pr_xref)
    |> reviews_status(toml)


    Logger.info("Code review status: Label Check #{passed_label} Passed Status: #{passed_status} Passed Review: #{passed_review} CODEOWNERS: #{code_owners_approved}")

    case {passed_label, passed_status, passed_review, code_owners_approved} do
      {true, true, :sufficient, true} -> :ok
      {false, _, _, _}             -> {:error, :blocked_labels}
      {_, false, _, _}             -> {:error, :pr_status}
      {_, _, :insufficient, _}     -> {:error, :insufficient_approvals}
      {_, _, :failed, _}           -> {:error, :blocked_review}
      {_, _, _, false}             -> {:error, :missing_code_owner_approval}
    end
  end

  @spec reviews_status(map, Batcher.BorsToml.t) :: :sufficient | :failed | :insufficient
  defp reviews_status(reviews, toml) do
    failed = Map.fetch!(reviews, "CHANGES_REQUESTED")
    approvals = Map.fetch!(reviews, "APPROVED")

    review_required? = is_integer(toml.required_approvals)
    approvals_needed = review_required? && toml.required_approvals || 0
    approved? = approvals >= approvals_needed
    failed? = failed > 0
    cond do
      # NOTE: A way to disable the code reviewing behaviour was requested on #587.
      #   As such, we only apply the reviewing rules if, on bors, the config
      #   `required_approvals` is present and an integer.
      not review_required? ->
        :sufficient
      failed? ->
        :failed
      approved? ->
        :sufficient
      review_required? ->
        :insufficient
    end
  end

  defp clone_batch(patch_links, project_id, into_branch) do
    batch = Repo.insert!(Batch.new(project_id, into_branch))
    patch_links
    |> Enum.map(&%{
      batch_id: batch.id,
      patch_id: &1.patch_id,
      reviewer: &1.reviewer})
    |> Enum.map(&LinkPatchBatch.changeset(%LinkPatchBatch{}, &1))
    |> Enum.each(&Repo.insert!/1)
    batch
  end

  def get_new_batch(project_id, into_branch, priority) do
    Batch
    |> where([b], b.project_id == ^project_id)
    |> where([b], b.state == ^(:waiting))
    |> where([b], b.into_branch == ^into_branch)
    |> where([b], b.priority == ^priority)
    |> order_by([b], [desc: b.updated_at])
    |> limit(1)
    |> Repo.all()
    |> case do
      [batch] -> {batch, false}
      _ -> {Repo.insert!(Batch.new(project_id, into_branch, priority)), true}
    end
  end

  defp raise_batch_priority(%Batch{priority: old_priority} = batch, priority) when old_priority < priority do
    project = Repo.get!(Project, batch.project_id)
    batch = batch
    |> Batch.changeset_raise_priority(%{priority: priority})
    |> Repo.update!()
    put_incomplete_on_hold(get_repo_conn(project), batch)
  end
  defp raise_batch_priority(_, _) do
    :ok
  end

  defp send_message(repo_conn, patches, message) do
    body = Batcher.Message.generate_message(message)
    Enum.each(patches, &GitHub.post_comment!(
      repo_conn,
      &1.pr_xref,
      body))
  end

  defp send_status(
         repo_conn,
         %Batch{id: id, commit: commit, project_id: project_id},
         message
       ) do
    patches = id
    |> Patch.all_for_batch()
    |> Repo.all()
    send_status(repo_conn, id, patches, message)
    unless is_nil commit do
      {msg, status} = Batcher.Message.generate_status(message)
      repo_conn
      |> GitHub.post_commit_status!({
        commit,
        status,
        msg,
        project_url(Endpoint, :log, project_id) <> "#batch-#{id}"})
    end
  end
  defp send_status(repo_conn, batch_id,  patches, message) do
    {msg, status} = Batcher.Message.generate_status(message)
    Enum.each(patches, &GitHub.post_commit_status!(
      repo_conn,
      {
        &1.commit,
        status,
        msg,
        project_url(Endpoint, :log, &1.project_id) <> "#batch-#{batch_id}"}))
  end

  @spec get_repo_conn(%Project{}) :: {{:installation, number}, number}
  defp get_repo_conn(project) do
    Project.installation_connection(project.repo_xref, Repo)
  end

  defp put_incomplete_on_hold(repo_conn, batch) do
    batches = batch.project_id
    |> Batch.all_for_project(:running)
    |> where([b], b.id != ^batch.id and b.priority < ^batch.priority)
    |> Repo.all()

    ids = Enum.map(batches, &(&1.id))

    Status
    |> where([s], s.batch_id in ^ids)
    |> Repo.delete_all()

    
    Enum.each(batches, &send_status(repo_conn, &1, :delayed))
    Batch
    |> where([b], b.id in ^ids)
    |> Repo.update_all(set: [state: :waiting])
  end

  defp poll_after_delay(project) do
    poll_at = (project.batch_delay_sec + 1) * 1000
    Process.send_after(self(), {:poll, :once}, poll_at)
  end
end
