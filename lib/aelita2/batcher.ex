defmodule Aelita2.Batcher do
  use GenServer

  alias Aelita2.Repo
  alias Aelita2.Batch
  alias Aelita2.Patch
  alias Aelita2.Status
  alias Aelita2.Integration.GitHub
  alias Aelita2.LinkPatchBatch

  @poll_period 1000

  # Public API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: Aelita2.Batcher)
  end

  def reviewed(patch_id) do
    GenServer.cast(Aelita2.Batcher, {:reviewed, patch_id})
  end

  def status(commit, identifier, state) do
    GenServer.cast(Aelita2.Batcher, {:status, commit, identifier, state})
  end

  # Server callbacks

  def init(:ok) do
    Process.send_after(self(), :poll, @poll_period)
    {:ok, :ok}
  end

  def handle_cast({:reviewed, patch}, :ok) do
    batch = get_new_batch(patch.project_id)
    project_id = batch.project_id
    ^project_id = patch.project_id
    LinkPatchBatch.changeset(%LinkPatchBatch{}, %{batch_id: batch.id, patch_id: patch.id})
    |> Repo.insert!()
    {:noreply, :ok}
  end

  def handle_cast({:status, commit, identifier, state}, :ok) do
    batch = Repo.all(Batch.get_assoc_by_commit(commit))
    case batch do
      [batch] ->
        Status.get_for_batch(batch.id, identifier)
        |> Repo.update_all([set: [state: Status.numberize_state(state)]])
        maybe_complete_batch(batch)
      [] -> :ok
    end
    {:noreply, :ok}
  end

  def handle_info(:poll, :ok) do
    poll_all()
    Process.send_after(self(), :poll, @poll_period)
    {:noreply, :ok}
  end

  # Private implementation details

  defp poll_all() do
    Repo.all(Batch.all_assoc(:incomplete))
    |> Enum.reduce(%{}, &add_batch_to_project_map/2)
    |> Enum.each(&poll_batches/1)
  end

  defp add_batch_to_project_map(batch, project_map) do
    project_id = batch.project_id
    {_, map} = Map.get_and_update(project_map, project_id, &prepend_or_new(&1, batch))
    map
  end

  # This wouldn't be a bad idea for the standard library.
  defp prepend_or_new(list, item) do
    new = if is_nil(list) do
      [item]
    else
      [item | list]
    end
    {item, new}
  end

  defp poll_batches({_project_id, batches}) do
    batches = Enum.sort_by(batches, &{-&1.state, &1.last_polled})
    poll_batches(batches)
  end

  defp poll_batches([%Batch{state: 0} | _] = batches) do
    Enum.each(batches, fn batch -> 0 = batch.state end)
    case Enum.filter(batches, &next_poll_is_past/1) do
      [] -> :ok
      [batch | _] -> start_waiting_batch(batch)
    end
  end

  defp poll_batches([%Batch{state: 1} | _] = batches) do
    Enum.filter(batches, &(&1.state == 1))
    |> Enum.filter(&next_poll_is_past/1)
    |> Enum.each(&poll_running_batch/1)
  end

  defp start_waiting_batch(batch) do
    project = batch.project
    token = GitHub.get_installation_token!(project.installation.installation_xref)
    stmp = "#{project.staging_branch}.tmp"
    patches = Repo.all(Patch.all_for_batch(batch.id))
    base = GitHub.copy_branch!(token, project.repo_xref, project.master_branch, stmp)
    do_merge_patch = fn patch, _branch ->
      GitHub.merge_branch!(token, project.repo_xref, patch.commit, stmp, "tmp")
    end
    head = Enum.reduce(patches, base, do_merge_patch)
    parents = [base | Enum.map(patches, &(&1.commit))]
    commit_title = Enum.reduce(patches, "Merge", &"#{&2} \##{&1.pr_xref}")
    commit_body = Enum.reduce(patches, "", &"#{&2}#{&1.title}\n")
    commit_message = "#{commit_title}\n\n#{commit_body}"
    commit = GitHub.synthesize_commit!(token, project.repo_xref, project.staging_branch, head.tree, parents, commit_message)
    batch = Batch.changeset(batch, %{state: Batch.numberize_state(:running), commit: commit, last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)})
    |> Repo.update!()
    setup_statuses(token, project, batch, patches)
  end

  defp setup_statuses(token, project, batch, patches) do
    toml = GitHub.get_file(token, project.repo_xref, project.staging_branch, "bors.toml")
    case toml do
      nil -> setup_statuses_error(token, project, batch, patches, "bors.toml does not exist")
      toml ->
        case :etoml.parse(toml) do
          {:ok, toml} ->
            setup_statuses_ok(token, project, batch, patches, toml)
          {:error, error} ->
            setup_statuses_error(token, project, batch, patches, error)
        end
    end
  end

  defp setup_statuses_ok(_token, _project, batch, _patches, toml) do
    Enum.map(toml["status"], &%Status{
      batch_id: batch.id,
      identifier: &1,
      url: nil,
      state: Status.numberize_state(:waiting)
      })
    |> Enum.each(&Repo.insert!/1)
  end

  defp setup_statuses_error(token, project, batch, patches, message) do
    Batch.changeset(batch, %{state: Batch.numberize_state(:err)})
    |> Repo.update!()
    body = "# Configuration problem\n\n#{message}"
    Enum.each(patches, &GitHub.post_comment!(token, project.repo_xref, &1.pr_xref, body))
  end

  defp poll_running_batch(batch) do
    project = batch.project
    token = GitHub.get_installation_token!(project.installation.installation_xref)
    my_statuses = Repo.all(Status.all_for_batch(batch.id))
    gh_statuses = GitHub.get_commit_status!(token, project.repo_xref, batch.commit)
    Enum.filter(my_statuses, &Map.has_key?(gh_statuses, &1.identifier))
    |> Enum.map(&Status.changeset(&1, %{state: Status.numberize_state(Map.fetch!(my_statuses, &1.identifier))}))
    |> Enum.each(&Repo.update!/1)
    Batch.changeset(batch, %{last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)})
    |> Repo.update!()
    maybe_complete_batch(batch)
  end

  defp maybe_complete_batch(batch) do
    not_completed = Repo.all(Status.all_for_batch(batch.id, :incomplete))
    if not_completed == [] do
      erred = Repo.all(Status.all_for_batch(batch.id, :err))
      state = if erred == [] do
        complete_batch(batch)
        :ok
      else
        fail_batch(batch, erred)
        :err
      end
      Batch.changeset(batch, %{status: Batch.numberize_state(state)})
      |> Repo.update!()
    end
  end

  defp complete_batch(batch) do
    project = batch.project
    token = GitHub.get_installation_token!(project.installation.installation_xref)
    GitHub.copy_branch!(token, project.repo_xref, project.staging_branch, project.master_branch)
  end

  defp fail_batch(_batch, _erred) do
    :ok
  end

  def get_new_batch(project_id) do
    case Repo.get_by(Batch, project_id: project_id, state: 0) do
      nil -> 
        Repo.insert!(%Batch{
          project_id: project_id,
          commit: nil,
          state: 0,
          last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)
        })
      batch -> batch
    end
  end

  defp next_poll_is_past(batch) do
    next = get_next_poll_unix_sec(batch)
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    next < now
  end

  defp get_next_poll_unix_sec(batch) do
    period = if Batch.atomize_state(batch.state) == :waiting do
      batch.project.batch_delay_sec
    else
      batch.project.batch_poll_period_sec
    end
    batch.last_polled + period
  end
end
