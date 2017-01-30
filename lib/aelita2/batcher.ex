defmodule Aelita2.Batcher do
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

  alias Aelita2.Repo
  alias Aelita2.Batch
  alias Aelita2.Batcher
  alias Aelita2.Patch
  alias Aelita2.Project
  alias Aelita2.Status
  alias Aelita2.LinkPatchBatch
  alias Aelita2.GitHub

  # Every half-hour
  @poll_period 30*60*1000

  # Public API

  def start_link(project_id) do
    GenServer.start_link(__MODULE__, project_id)
  end

  def reviewed(pid, patch_id) when is_integer(patch_id) do
    GenServer.cast(pid, {:reviewed, patch_id})
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
    Process.send_after(self(), :poll, @poll_period)
    {:ok, project_id}
  end

  def handle_cast(args, project_id) do
    Repo.transaction(fn -> do_handle_cast(args, project_id) end)
    {:noreply, project_id}
  end

  def do_handle_cast({:reviewed, patch_id}, project_id) do
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
        batch = get_new_batch(project_id)
        params = %{batch_id: batch.id, patch_id: patch.id}
        Repo.insert!(LinkPatchBatch.changeset(%LinkPatchBatch{}, params))
        Process.send_after(self(), :poll, (project.batch_delay_sec + 1) * 1000)
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

  def do_handle_cast({:cancel, patch_id}, project_id) do
    batch = patch_id
    |> Batch.all_for_patch(:incomplete)
    |> Repo.one!()
    ^project_id = batch.project_id
    if batch.state == Batch.numberize_state(:running) do
      cancel_batch(batch, patch_id)
    else
      LinkPatchBatch
      |> Repo.get_by!(batch_id: batch.id, patch_id: patch_id)
      |> Repo.delete!()
      if Batch.is_empty(batch.id, Repo) do
        Repo.delete!(batch)
      end
    end
  end

  def do_handle_cast({:cancel_all}, project_id) do
    canceled = Batch.numberize_state(:canceled)
    project_id
    |> Batch.all_for_project(:waiting)
    |> Repo.all()
    |> Enum.each(&Repo.delete!/1)
    project_id
    |> Batch.all_for_project(:running)
    |> Repo.all()
    |> Enum.map(&Batch.changeset(&1, %{state: canceled}))
    |> Enum.each(&Repo.update!/1)
  end

  def handle_info(:poll, project_id) do
    Repo.transaction(fn -> poll(project_id) end)
    Process.send_after(self(), :poll, @poll_period)
    {:noreply, project_id}
  end

  # Private implementation details

  defp poll(project_id) do
    project = Repo.get(Project, project_id)
    project_id
    |> Batch.all_for_project(:incomplete)
    |> Repo.all()
    |> Enum.map(&%Batch{&1 | project: project})
    |> sort_batches()
    |> poll_batches()
  end

  def sort_batches(batches) do
    sorted_batches = Enum.sort_by(batches, &{-&1.state, &1.last_polled})
    new_batches = Enum.dedup_by(sorted_batches, &(&1.id))
    state = if new_batches != [] and hd(new_batches).state == 1 do
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
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    project = batch.project
    stmp = "#{project.staging_branch}.tmp"
    repo_conn = get_repo_conn(project)
    base = GitHub.copy_branch!(
      repo_conn,
      project.master_branch,
      stmp)
    do_merge_patch = fn patch, branch ->
      case branch do
        :conflict -> :conflict
        _ -> GitHub.merge_branch!(
          repo_conn,
          %{
            from: patch.commit,
            to: stmp,
            commit_message: "-bors-staging-tmp-#{patch.pr_xref}"
          })
      end
    end
    head = with(
      %{tree: tree} <- Enum.reduce(patches, base, do_merge_patch),
      parents <- [base | Enum.map(patches, &(&1.commit))],
      commit_message <- Batcher.Message.generate_commit_message(patches),
      do: GitHub.synthesize_commit!(
        repo_conn,
        %{
          branch: project.staging_branch,
          tree: tree,
          parents: parents,
          commit_message: commit_message}))
    case head do
      :conflict ->
        state = bisect(patches, project)
        send_message(repo_conn, patches, {:conflict, state})
        err = Batch.numberize_state(:error)
        batch
        |> Batch.changeset(%{state: err})
        |> Repo.update!()
      commit ->
        state = setup_statuses(repo_conn, batch, patches)
        state = Batch.numberize_state(state)
        now = DateTime.to_unix(DateTime.utc_now(), :seconds)
        batch
        |> Batch.changeset(%{state: state, commit: commit, last_polled: now})
        |> Repo.update!()
    end
    Project.ping!(project.id)
  end

  defp setup_statuses(repo_conn, batch, patches) do
    toml = GitHub.get_file!(
      repo_conn,
      batch.project.staging_branch,
      "bors.toml")
    case toml do
      nil ->
        setup_statuses_error(
          repo_conn,
          batch,
          patches,
          :fetch_failed)
        :error
      toml ->
        case Aelita2.Batcher.BorsToml.new(toml) do
          {:ok, toml} ->
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
            :running
          {:error, message} ->
            setup_statuses_error(repo_conn,
              batch,
              patches,
              message)
            :error
        end
    end
  end

  defp setup_statuses_error(repo_conn, batch, patches, message) do
    message = Batcher.Message.generate_bors_toml_error(message)
    err = Batch.numberize_state(:error)
    batch
    |> Batch.changeset(%{state: err})
    |> Repo.update!()
    send_message(repo_conn, patches, {:config, message})
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
    state = Aelita2.Batcher.State.summary_statuses(statuses)
    maybe_complete_batch(state, batch, statuses)
    state = Batch.numberize_state(state)
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    batch
    |> Batch.changeset(%{state: state, last_polled: now})
    |> Repo.update!()
  end

  defp maybe_complete_batch(:ok, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    GitHub.push!(
      repo_conn,
      batch.commit,
      project.master_branch)
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    send_message(repo_conn, patches, {:succeeded, statuses})
    Project.ping!(project.id)
  end

  defp maybe_complete_batch(:error, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    erred = Enum.filter(statuses, &(&1.state == Status.numberize_state(:error)))
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    state = bisect(patches, project)
    send_message(repo_conn, patches, {state, erred})
    Project.ping!(project.id)
  end

  defp maybe_complete_batch(:running, _batch, _erred) do
    :ok
  end

  defp timeout_batch(batch) do
    project = batch.project
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    state = bisect(patches, project)
    project
    |> get_repo_conn()
    |> send_message(patches, {:timeout, state})
    err = Batch.numberize_state(:error)
    batch
    |> Batch.changeset(%{state: err})
    |> Repo.update!()
    Project.ping!(project.id)
  end

  defp cancel_batch(batch, patch_id) do
    project = batch.project
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    state = case tl(patches) do
      [] -> :failed
      _ -> :retrying
    end
    project
    |> get_repo_conn()
    |> send_message(patches, {:canceled, state})
    canceled = Batch.numberize_state(:canceled)
    batch
    |> Batch.changeset(%{status: canceled})
    |> Repo.update!()
    if state == :retrying do
      patches
      |> Enum.filter(&(&1.id == patch_id))
      |> make_batch(project.id)
    end
    Project.ping!(project.id)
  end

  defp bisect(patches, project) do
    count = Enum.count(patches)
    if count > 1 do
      {patches_lo, patches_hi} = Enum.split(patches, div(count, 2))
      make_batch(patches_lo, project.id)
      make_batch(patches_hi, project.id)
      :retrying
    else
      :failed
    end
  end

  defp make_batch(patches, project_id) do
    batch = Repo.insert!(Batch.new(project_id))
    patches
    |> Enum.map(&%{batch_id: batch.id, patch_id: &1.id})
    |> Enum.map(&LinkPatchBatch.changeset(%LinkPatchBatch{}, &1))
    |> Enum.each(&Repo.insert!/1)
    batch
  end

  def get_new_batch(project_id) do
    waiting = Batch.numberize_state(:waiting)
    case Repo.get_by(Batch, project_id: project_id, state: waiting) do
      nil -> Repo.insert!(Batch.new(project_id))
      batch -> batch
    end
  end

  defp send_message(repo_conn, patches, message) do
    body = Batcher.Message.generate_message(message)
    Enum.each(patches, &GitHub.post_comment!(
      repo_conn,
      &1.pr_xref,
      body))
  end

  @spec get_repo_conn(%Project{}) :: {{:installation, number}, number}
  defp get_repo_conn(project) do
    Project.installation_connection(project.repo_xref, Repo)
  end
end
