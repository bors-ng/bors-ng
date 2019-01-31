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
        |> send_message([patch], :not_awaiting_review)
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
          commit_message: "[ci skip]",
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
            commit_message: "[ci skip] -bors-staging-tmp-#{patch.pr_xref}"})
      end
    end
    merge = Enum.reduce(patch_links, tbase, do_merge_patch)
    {status, commit} = start_waiting_merged_batch(
      batch,
      patch_links,
      base,
      merge)
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
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
        parents = [base.commit | Enum.map(patch_links, &(&1.patch.commit))]
        commit_message = Batcher.Message.generate_commit_message(
          patch_links,
          toml.cut_body_after,
          gather_co_authors(batch, patch_links))
        head = GitHub.synthesize_commit!(
          repo_conn,
          %{
            branch: batch.project.staging_branch,
            tree: tree,
            parents: parents,
            commit_message: commit_message,
            committer: toml.committer})
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
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
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
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
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

  defp complete_batch(:ok, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    {:ok, _} = push_with_retry(
      repo_conn,
      batch.commit,
      batch.into_branch)
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()

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
    passed_review = if is_nil(toml.required_approvals) do
      :sufficient
    else
      repo_conn
      |> GitHub.get_reviews!(patch.pr_xref)
      |> are_reviews_passing(toml.required_approvals)
    end
    case {passed_label, passed_status, passed_review} do
      {true, true, :sufficient} -> :ok
      {false, _, _}             -> {:error, :blocked_labels}
      {_, false, _}             -> {:error, :pr_status}
      {_, _, :insufficient}     -> {:error, :insufficient_approvals}
      {_, _, :failed}           -> {:error, :blocked_review}
    end
  end

  defp are_reviews_passing(reviews, required) do
    %{"CHANGES_REQUESTED" => failed, "APPROVED" => passed} = reviews

    case {failed, passed} do
      {failed, 0} when failed > 0 -> :failed
      {_, approved} when approved >= required -> :sufficient
      {0, _} -> :insufficient
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
    batches_query = batch.project_id
    |> Batch.all_for_project(:running)
    |> where([b], b.id != ^batch.id and b.priority < ^batch.priority)
    Status
    |> join(:inner, [s], b in ^batches_query, s.batch_id == b.id)
    |> Repo.delete_all()
    batches_query
    |> Repo.all()
    |> Enum.each(&send_status(repo_conn, &1, :delayed))
    Repo.update_all(batches_query,
      set: [state: :waiting])
  end

  defp poll_after_delay(project) do
    poll_at = (project.batch_delay_sec + 1) * 1000
    Process.send_after(self(), {:poll, :once}, poll_at)
  end
end
