defmodule Aelita2.Batcher do
  use GenServer

  alias Aelita2.Repo
  alias Aelita2.Batch
  alias Aelita2.Patch
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
    LinkPatchBatch.changeset(%LinkPatchBatch{}, %{batch_id: batch.id, patch_id: patch.id})
    |> Repo.insert!()
  end

  def do_handle_cast({:status, commit, identifier, state, url}) do
    batch = Repo.all(Batch.get_assoc_by_commit(commit))
    case batch do
      [batch] ->
        Status.get_for_batch(batch.id, identifier)
        |> Repo.update_all([set: [state: Status.numberize_state(state), url: url]])
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

  defp poll_all() do
    Repo.all(Batch.all_assoc(:incomplete))
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
    patches = Repo.all(Patch.all_for_batch(batch.id))
    |> Enum.map(&%Patch{&1 | project: batch.project})
    project = batch.project
    token = @github_api.Integration.get_installation_token!(project.installation.installation_xref)
    stmp = "#{project.staging_branch}.tmp"
    base = @github_api.copy_branch!(token, project.repo_xref, project.master_branch, stmp)
    do_merge_patch = fn patch, _branch ->
      @github_api.merge_branch!(token, project.repo_xref, patch.commit, stmp, "tmp")
    end
    head = Enum.reduce(patches, base, do_merge_patch)
    parents = [base | Enum.map(patches, &(&1.commit))]
    commit_title = Enum.reduce(patches, "Merge", &"#{&2} \##{&1.pr_xref}")
    commit_body = Enum.reduce(patches, "", &"#{&2}#{&1.pr_xref}: #{&1.title}\n")
    commit_message = "#{commit_title}\n\n#{commit_body}"
    commit = @github_api.synthesize_commit!(token, project.repo_xref, project.staging_branch, head.tree, parents, commit_message)
    setup_statuses(token, project, batch, patches)
    Batch.changeset(batch, %{state: Batch.numberize_state(:running), commit: commit, last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)})
    |> Repo.update!()
  end

  defp setup_statuses(token, project, batch, patches) do
    toml = @github_api.get_file(token, project.repo_xref, project.staging_branch, "bors.toml")
    case toml do
      nil -> setup_statuses_error(token, project, batch, patches, "bors.toml does not exist")
      toml ->
        case Aelita2.Batcher.BorsToml.new(toml) do
          {:ok, toml} ->
            setup_statuses_ok(token, project, batch, patches, toml)
          {:err, :parse_failed} ->
            setup_statuses_error(token, project, batch, patches, "bors.toml is invalid")
        end
    end
  end

  defp setup_statuses_ok(_token, _project, batch, _patches, toml) do
    Enum.map(toml.status, &%Status{
      batch_id: batch.id,
      identifier: &1,
      url: nil,
      state: Status.numberize_state(:waiting)
      })
    |> Enum.each(&Repo.insert!/1)
  end

  defp setup_statuses_error(token, _project, batch, patches, message) do
    Batch.changeset(batch, %{state: Batch.numberize_state(:err)})
    |> Repo.update!()
    Aelita2.Batcher.Message.send(token, patches, {:config, message})
  end

  defp poll_running_batch(batch) do
    project = batch.project
    token = @github_api.Integration.get_installation_token!(project.installation.installation_xref)
    my_statuses = Repo.all(Status.all_for_batch(batch.id))
    gh_statuses = @github_api.get_commit_status!(token, project.repo_xref, batch.commit)
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
        succeeded = Repo.all(Status.all_for_batch(batch.id, :ok))
        complete_batch(batch, succeeded)
        :ok
      else
        fail_batch(batch, erred)
        :err
      end
      Batch.changeset(batch, %{state: Batch.numberize_state(state)})
      |> Repo.update!()
    end
  end

  defp complete_batch(batch, succeeded) do
    project = batch.project
    token = @github_api.Integration.get_installation_token!(project.installation.installation_xref)
    @github_api.copy_branch!(token, project.repo_xref, project.staging_branch, project.master_branch)
    patches = Repo.all(Patch.all_for_batch(batch.id))
    |> Enum.map(&%Patch{&1 | project: batch.project})
    Aelita2.Batcher.Message.send(token, patches, {:succeeded, succeeded})
  end

  defp fail_batch(batch, erred) do
    project = batch.project
    token = @github_api.Integration.get_installation_token!(project.installation.installation_xref)
    patches = Repo.all(Patch.all_for_batch(batch.id))
    |> Enum.map(&%Patch{&1 | project: batch.project})
    count = Enum.count(patches)
    state = if count > 1 do
      {patches_lo, patches_hi} = Enum.split(patches, div(count, 2))
      make_batch(patches_lo, project.id)
      make_batch(patches_hi, project.id)
      :retrying
    else
      :failed
    end
    Aelita2.Batcher.Message.send(token, patches, {state, erred})
  end

  defp make_batch(patches, project_id) do
    batch = Repo.insert!(Batch.new(project_id))
    Enum.map(patches, &LinkPatchBatch.changeset(%LinkPatchBatch{}, %{batch_id: batch.id, patch_id: &1.id}))
    |> Enum.each(&Repo.insert!/1)
    batch
  end

  def get_new_batch(project_id) do
    case Repo.get_by(Batch, project_id: project_id, state: Batch.numberize_state(:waiting)) do
      nil -> Repo.insert!(Batch.new(project_id))
      batch -> batch
    end
  end
end
