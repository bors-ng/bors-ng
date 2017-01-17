defmodule Aelita2.Batcher do
  @moduledoc """
  The "Batcher" manages the backlog of batches that each project has.
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

  @poll_period 1000
  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]

  # Public API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: Aelita2.Batcher)
  end

  def reviewed(patch_id) when is_integer(patch_id) do
    GenServer.cast(Aelita2.Batcher, {:reviewed, patch_id})
  end

  def status(commit, identifier, state, url) do
    GenServer.cast(Aelita2.Batcher, {:status, commit, identifier, state, url})
  end

  # Server callbacks

  def init(:ok) do
    Process.send_after(self(), :poll, @poll_period)
    {:ok, :ok}
  end

  def handle_cast(args, state) do
    Repo.transaction(fn -> do_handle_cast(args) end)
    {:noreply, state}
  end

  def do_handle_cast({:reviewed, patch_id}) do
    patch = Repo.get!(Patch.all(:awaiting_review), patch_id)
    batch = get_new_batch(patch.project_id)
    project_id = batch.project_id
    ^project_id = patch.project_id
    params = %{batch_id: batch.id, patch_id: patch.id}
    Repo.insert!(LinkPatchBatch.changeset(%LinkPatchBatch{}, params))
  end

  def do_handle_cast({:status, commit, identifier, state, url}) do
    batch = Repo.all(Batch.get_assoc_by_commit(commit))
    state = Status.numberize_state(state)
    case batch do
      [batch] ->
        batch.id
        |> Status.get_for_batch(identifier)
        |> Repo.update_all([set: [state: state, url: url]])
        if batch.state == Batch.numberize_state(:running) do
          maybe_complete_batch(batch)
        end
      [] -> :ok
    end
  end

  def handle_info(:poll, :ok) do
    Repo.transaction(&poll_all/0)
    Process.send_after(self(), :poll, @poll_period)
    {:noreply, :ok}
  end

  # Private implementation details

  defp poll_all do
    :incomplete
    |> Batch.all_assoc()
    |> Repo.all()
    |> Aelita2.Batcher.Queue.organize_batches_into_project_queues()
    |> Enum.each(&poll_batches/1)
  end

  defp poll_batches({:waiting, batches}) do
    case Enum.filter(batches, &Batch.next_poll_is_past/1) do
      [] -> :ok
      [batch | _] -> start_waiting_batch(batch)
    end
  end

  defp poll_batches({:running, batches}) do
    batch = hd(batches)
    if Batch.next_poll_is_past(batch) do
      poll_running_batch(batch)
    end
  end

  defp start_waiting_batch(batch) do
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    project = batch.project
    stmp = "#{project.staging_branch}.tmp"
    repo_conn = get_repo_conn(project)
    base = @github_api.copy_branch!(
      repo_conn,
      project.master_branch,
      stmp)
    do_merge_patch = fn patch, branch ->
      case branch do
        :conflict -> :conflict
        _ -> @github_api.merge_branch!(
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
      do: @github_api.synthesize_commit!(
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
    toml = @github_api.get_file(
      repo_conn,
      batch.project.staging_branch,
      "bors.toml")
    case toml do
      nil ->
        setup_statuses_error(
          repo_conn,
          batch,
          patches,
          "bors.toml does not exist")
        :err
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
            :running
          {:err, :parse_failed} ->
            setup_statuses_error(repo_conn,
              batch,
              patches,
              "bors.toml is invalid")
            :err
        end
    end
  end

  defp setup_statuses_error(repo_conn, batch, patches, message) do
    err = Batch.numberize_state(:err)
    batch
    |> Batch.changeset(%{state: err})
    |> Repo.update!()
    send_message(repo_conn, patches, {:config, message})
  end

  defp poll_running_batch(batch) do
    project = batch.project
    gh_statuses = project
    |> get_repo_conn()
    |> @github_api.get_commit_status!(batch.commit)
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
    @github_api.push!(
      repo_conn,
      batch.commit,
      project.master_branch)
    patches = batch.id
    |> Patch.all_for_batch()
    |> Repo.all()
    send_message(repo_conn, patches, {:succeeded, statuses})
    Project.ping!(project.id)
  end

  defp maybe_complete_batch(:err, batch, statuses) do
    project = batch.project
    repo_conn = get_repo_conn(project)
    erred = Enum.filter(statuses, &(&1.state == Status.numberize_state(:err)))
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
    Enum.each(patches, &@github_api.post_comment!(
      repo_conn,
      &1.pr_xref,
      body))
  end

  defp get_repo_conn(project) do
    project.repo_xref
    |> Project.installation_connection()
    |> Repo.one!()
    |> @github_api.RepoConnection.connect!()
  end
end
