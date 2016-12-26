defmodule Aelita2.Batcher do
  use GenServer

  alias Aelita2.Repo
  alias Aelita2.Batch
  alias Aelita2.Patch
  alias Aelita2.Status
  alias Aelita2.Integration.GitHub

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
    Patch.changeset(patch, %{batch_id: batch.id}) |> Repo.update!()
    {:noreply, :ok}
  end

  def handle_cast({:status, commit, identifier, state}, :ok) do
    batch = Repo.get_by(Batch, commit: commit)
    Status.get_for_project(batch.project_id, identifier)
    |> Repo.update_all([set: [state: Status.state_numberize(state)]])
    {:noreply, :ok}
  end

  def handle_info(:poll, :ok) do
    poll_all()
    Process.send_after(self(), :poll, @poll_period)
    {:noreply, :ok}
  end

  # Private implementation details

  defp poll_all() do
    batches = Repo.all(Batch, preload: :project, preload: :'project.installation')
    batches
    |> Enum.reduce(%{}, &add_batch_to_project_map/2)
    |> Enum.each(&poll_batches/1)
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
    stmp = "#{project.staging_branch}/tmp"
    patches = Repo.all(Patch.all_for_batch(batch.id))
    base = GitHub.copy_branch!(token, project.repo_xref, project.master_branch, stmp)
    head = Enum.reduce(patches, &GitHub.merge_branch!(token, project.repo_xref, &1.commit, stmp, "tmp"))
    parents = [base | Enum.map(patches, &(&1.commit))]
    commit_title = Enum.reduce(patches, "Merge", &"#{&2} #{&1.pr_xref}")
    commit_body = Enum.reduce(patches, "", &"#{&2}#{&1.title}\n")
    commit_message = "#{commit_title}\n\n#{commit_body}"
    commit = GitHub.synthesize_commit!(token, project.repo_xref, project.staging_branch, head.tree, parents, commit_message)
    Status.all_for_project(project.id)
    |> Repo.update_all([set: [state: 1]])
    Batch.changeset(batch, %{state: 1, commit: commit, last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)})
    |> Repo.update!()
  end

  defp poll_running_batch(batch) do
    project = batch.project
    token = GitHub.get_installation_token!(project.installation.installation_xref)
    my_statuses = Repo.all(Status.all_for_project(project.id))
    gh_statuses = GitHub.get_commit_status!(token, project.repo_xref, batch.commit)
    Enum.filter(my_statuses, &Map.has_key?(gh_statuses, &1.identifier))
    |> Enum.map(&Status.changeset(&1, %{state: Status.state_numberize(Map.fetch!(my_statuses, &1.identifier))}))
    |> Enum.each(&Repo.update!/1)
    Batch.changeset(batch, %{last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)})
    |> Repo.update!()
    maybe_complete_batch(batch)
  end

  defp maybe_complete_batch(batch) do
    project = batch.project
    not_completed = Repo.all(Status.all_for_project(project.id, :incomplete))
    if not_completed == [] do
      complete_batch(batch)
    end
  end

  defp complete_batch(batch) do
    project = batch.project
    token = GitHub.get_installation_token!(project.installation.installation_xref)
    GitHub.copy_branch!(token, project.repo_xref, project.staging_branch, project.master_branch)
  end

  defp add_batch_to_project_map(batch, project_map) do
    project_id = batch.project_id
    Map.get_and_update(project_map, project_id, &prepend_or_new(&1, batch))
  end

  # This wouldn't be a bad idea for the standard library.
  defp prepend_or_new(list, item) do
    if is_nil(list) do
      [item]
    else
      [item | list]
    end
  end

  def get_new_batch(project_id) do
    delayed_batch = Repo.get_by(Batch, project_id: project_id, state: 0)
    case delayed_batch do
      {:ok, batch} -> batch
      {:err, _} -> 
        Repo.insert!(%Batch{
          project_id: project_id,
          commit: nil,
          state: 0,
          last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)
        })
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
    DateTime.to_unix(batch.last_polled, :seconds) + period
  end
end
