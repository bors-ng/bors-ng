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
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Status
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.GitHub
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

  def cancel(pid, patch_id) when is_integer(patch_id) do
    GenServer.cast(pid, {:cancel, patch_id})
  end

  def cancel_all(pid) do
    GenServer.cast(pid, {:cancel_all})
  end

  # Server callbacks

  def init(project_id) do
    Process.send_after(self(), {:poll, :repeat}, @poll_period)
    {:ok, project_id}
  end

  def handle_cast(args, project_id) do
    do_handle_cast(args, project_id)
    {:noreply, project_id}
  end

  def handle_call({:set_priority, patch_id, priority}, _from, state) do
    case Repo.get(Patch.all(:awaiting_review), patch_id) do
      nil -> nil
      patch ->
        if patch.priority != priority do
          patch
          |> Patch.changeset(%{priority: priority})
          |> Repo.update!()
        end
    end

    {:reply, :ok, state}
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
        if Patch.ci_skip?(patch) do
          project
          |> get_repo_conn()
          |> send_message([patch], :ci_skip)
        else

          {batch, is_new_batch} = get_new_batch(
            project_id,
            patch.into_branch,
            patch.priority
          )

          if is_new_batch do
            put_incomplete_on_hold(get_repo_conn(project), batch)
          end

          repo_conn = get_repo_conn(project)
          case patch_preflight(repo_conn, patch) do
            :ok ->
              params = %{
                batch_id: batch.id,
                patch_id: patch.id,
                reviewer: reviewer}
              Repo.insert!(LinkPatchBatch.changeset(%LinkPatchBatch{}, params))
              poll_at = (project.batch_delay_sec + 1) * 1000
              Process.send_after(self(), {:poll, :once}, poll_at)
              send_status(repo_conn, [patch], :waiting)
            {:error, message} ->
              send_message(repo_conn, [patch], {:preflight, message})
              send_status(repo_conn, [patch], :error)
          end
        end
    end
  end

  def do_handle_cast({:status, {commit, identifier, state, url}}, project_id) do
    batch = Repo.all(Batch.get_assoc_by_commit(commit))
    state = Status.numberize_state(state)
    case batch do
      [batch] ->
        ^project_id = batch.project_id
        batch.id
        |> Status.get_for_batch(identifier)
        |> Repo.update_all([set: [state: state, url: url]])
        if batch.state == Batch.numberize_state(:running) do
          maybe_complete_batch(batch)
        end
      [] -> :ok
    end
  end

  def do_handle_cast({:cancel, patch_id}, _project_id) do
    batch = patch_id
    |> Batch.all_for_patch(:incomplete)
    |> Repo.one()
    cancel_patch(batch, patch_id)
  end

  def do_handle_cast({:cancel_all}, project_id) do
    canceled = Batch.numberize_state(:canceled)
    waiting = project_id
    |> Batch.all_for_project(:waiting)
    |> Repo.all()
    Enum.each(waiting, &Repo.delete!/1)
    running = project_id
    |> Batch.all_for_project(:running)
    |> Repo.all()
    Enum.map(running, &Batch.changeset(&1, %{state: canceled}))
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
    case poll(project_id) do
      :stop ->
        {:stop, :normal, project_id}
      :again ->
        {:noreply, project_id}
    end
  end

  # Private implementation details

  defp poll(project_id) do
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
      -&1.state,
      -&1.priority,
      &1.last_polled
    })
    new_batches = Enum.dedup_by(sorted_batches, &(&1.id))
    running_state = Batch.numberize_state(:running)
    state = if new_batches != [] and hd(new_batches).state == running_state do
      :running
    else
      Enum.each(new_batches, fn batch -> 0 = batch.state end)
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
    stmp = "#{project.staging_branch}.tmp"
    base = GitHub.get_branch!(
      repo_conn,
      batch.into_branch)
    tbase = GitHub.synthesize_commit!(
      repo_conn,
      %{
        branch: stmp,
        tree: base.tree,
        parents: [base.commit],
        commit_message: "[ci skip]"})
    do_merge_patch = fn %{patch: patch}, branch ->
      case branch do
        :conflict -> :conflict
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
    state = Batch.numberize_state(status)
    batch
    |> Batch.changeset(%{state: state, commit: commit, last_polled: now})
    |> Repo.update!()
    Project.ping!(batch.project_id)
    status
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
          toml.cut_body_after)
        head = GitHub.synthesize_commit!(
          repo_conn,
          %{
            branch: batch.project.staging_branch,
            tree: tree,
            parents: parents,
            commit_message: commit_message})
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

  defp setup_statuses(batch, toml) do
    toml.status
    |> Enum.map(&%Status{
        batch_id: batch.id,
        identifier: &1,
        url: nil,
        state: Status.numberize_state(:running)})
    |> Enum.each(&Repo.insert!/1)
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    batch
    |> Batch.changeset(%{timeout_at: now + toml.timeout_sec})
    |> Repo.update!()
  end

  defp poll_running_batch(batch) do
    project = batch.project
    gh_statuses = project
    |> get_repo_conn()
    |> GitHub.get_commit_status!(batch.commit)
    |> Enum.map(&{elem(&1, 0), Status.numberize_state(elem(&1, 1))})
    |> Map.new()
    batch.id
    |> Status.all_for_batch()
    |> Repo.all()
    |> Enum.filter(&Map.has_key?(gh_statuses, &1.identifier))
    |> Enum.map(&{&1, %{state: Map.fetch!(gh_statuses, &1.identifier)}})
    |> Enum.map(&Status.changeset(elem(&1, 0), elem(&1, 1)))
    |> Enum.each(&Repo.update!/1)
    maybe_complete_batch(batch)
  end

  defp maybe_complete_batch(batch) do
    statuses = Repo.all(Status.all_for_batch(batch.id))
    status = Batcher.State.summary_database_statuses(statuses)
    state = Batch.numberize_state(status)
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    if status != :running do
      batch.project
      |> get_repo_conn()
      |> send_status(batch, status)
      Project.ping!(batch.project_id)
      complete_batch(status, batch, statuses)
    end
    batch
    |> Batch.changeset(%{state: state, last_polled: now})
    |> Repo.update!()
    if status != :running do
      poll(batch.project_id)
    end
  end

  defp complete_batch(:ok, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    GitHub.push!(
      repo_conn,
      batch.commit,
      batch.into_branch)
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()

    send_message(repo_conn, patches, {:succeeded, statuses})
    close_prs(repo_conn, patches)
  end

  defp complete_batch(:error, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    erred = Enum.filter(statuses, &(&1.state == Status.numberize_state(:error)))
    patch_links = batch.id
    |> LinkPatchBatch.from_batch()
    |> Repo.all()
    patches = Enum.map(patch_links, &(&1.patch))
    state = bisect(patch_links, batch)
    send_message(repo_conn, patches, {state, erred})
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
    err = Batch.numberize_state(:error)
    batch
    |> Batch.changeset(%{state: err})
    |> Repo.update!()
    Project.ping!(project.id)
    project
    |> get_repo_conn()
    |> send_status(batch, :timeout)
  end

  defp cancel_patch(nil, _), do: :ok

  defp cancel_patch(batch, patch_id) do
    cancel_patch(batch, patch_id, Batch.atomize_state(batch.state))
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
    canceled = Batch.numberize_state(:canceled)
    batch
    |> Batch.changeset(%{state: canceled})
    |> Repo.update!()
    if state == :retrying do
      patch_links
      |> Enum.filter(&(&1.patch_id == patch_id))
      |> clone_batch(project.id, batch.into_branch)
    end
    repo_conn = get_repo_conn(project)
    send_status(repo_conn, batch, :canceled)
    send_message(repo_conn, patches, {:canceled, state})
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
    send_status(repo_conn, [patch], :canceled)
    send_message(repo_conn, [patch], {:canceled, :failed})
  end

  defp bisect(patch_links, %Batch{project: project, into_branch: into}) do
    count = Enum.count(patch_links)
    if count > 1 do
      {lo, hi} = Enum.split(patch_links, div(count, 2))
      clone_batch(lo, project.id, into)
      clone_batch(hi, project.id, into)
      :retrying
    else
      :failed
    end
  end

  defp patch_preflight(repo_conn, patch) do
    toml = Batcher.GetBorsToml.get(
      repo_conn,
      patch.commit)
    patch_preflight(repo_conn, patch, toml)
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
    case {passed_label, passed_status} do
      {true, true} -> :ok
      {false, _} -> {:error, :blocked_labels}
      {_, false} -> {:error, :pr_status}
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
    waiting = Batch.numberize_state(:waiting)
    Batch
    |> Repo.get_by(
      project_id: project_id,
      state: waiting,
      into_branch: into_branch,
      priority: priority)
    |> case do
      nil -> {Repo.insert!(Batch.new(project_id, into_branch, priority)), true}
      batch -> {batch, false}
    end
  end

  defp send_message(repo_conn, patches, message) do
    body = Batcher.Message.generate_message(message)
    Enum.each(patches, &GitHub.post_comment!(
      repo_conn,
      &1.pr_xref,
      body))
  end

  defp send_status(repo_conn, %Batch{id: id, commit: commit}, message) do
    patches = id
    |> Patch.all_for_batch()
    |> Repo.all()
    send_status(repo_conn, patches, message)
    unless is_nil commit do
      {msg, status} = Batcher.Message.generate_status(message)
      repo_conn
      |> GitHub.post_commit_status!(commit, status, msg)
    end
  end
  defp send_status(repo_conn, patches, message) do
    {msg, status} = Batcher.Message.generate_status(message)
    Enum.each(patches, &GitHub.post_commit_status!(
      repo_conn,
      &1.commit,
      status,
      msg))
  end

  defp close_prs(repo_conn, patches) do
    Enum.each(patches, &GitHub.close_pr!(
      repo_conn,
      &1.pr_xref))
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
      set: [state: Batch.numberize_state(:waiting)])
  end
end
