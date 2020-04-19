defmodule BorsNG.Worker.Attemptor do
  @moduledoc """
  An "Attemptor" manages the set of running attempts (that is, "try jobs").
  It implements this set of rules:

    * When a patch is tried,
      We immediately merge it with master into the trying branch.
    * The project's CI is occasionally polled,
      if a attempt is currently running.
      After polling, the completion logic is run.
    * If a notification related to the underlying CI is received,
      the completion logic is run.
    * When the completion logic is run, the either succeeded or failed.
  """

  use GenServer

  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Attempt
  alias BorsNG.Database.AttemptStatus
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.GitHub

  # Every half-hour
  @poll_period 30 * 60 * 1000

  # Public API

  def start_link(project_id) do
    GenServer.start_link(__MODULE__, project_id)
  end

  def tried(pid, patch_id, arguments) when is_integer(patch_id) do
    GenServer.cast(pid, {:tried, patch_id, arguments})
  end

  def cancel(pid, patch_id) when is_integer(patch_id) do
    GenServer.cast(pid, {:cancel, patch_id})
  end

  def status(pid, stat) do
    GenServer.cast(pid, {:status, stat})
  end

  def poll(pid) do
    send(pid, :poll_once)
  end

  # Server callbacks

  def init(project_id) do
    Process.send_after(
      self(),
      :poll,
      trunc(@poll_period * :rand.uniform(2) * 0.5)
    )

    {:ok, project_id}
  end

  def handle_cast(args, project_id) do
    do_handle_cast(args, project_id)
    {:noreply, project_id}
  end

  def do_handle_cast({:tried, patch_id, arguments}, project_id) do
    patch = Repo.get!(Patch, patch_id)
    ^project_id = patch.project_id
    project = Repo.get!(Project, project_id)

    case Repo.all(Attempt.all_for_patch(patch_id, :incomplete)) do
      [] ->
        # There is no currently running attempt
        # Start one
        if Patch.ci_skip?(patch) do
          project
          |> get_repo_conn()
          |> send_message(patch, {:preflight, :ci_skip})
        else
          patch
          |> Attempt.new(arguments)
          |> Repo.insert!()
          |> maybe_start_attempt(project)
        end

      [_attempt | _] ->
        # There is already a running attempt
        project
        |> get_repo_conn()
        |> send_message(patch, :already_running_review)
    end
  end

  def do_handle_cast({:status, {commit, identifier, state, url}}, project_id) do
    project_id
    |> Attempt.get_by_commit(commit, :incomplete)
    |> Repo.all()
    |> case do
      [attempt] ->
        patch = Repo.get!(Patch, attempt.patch_id)
        ^project_id = patch.project_id
        project = Repo.get!(Project, project_id)

        attempt.id
        |> AttemptStatus.get_for_attempt(identifier)
        |> Repo.update_all(set: [state: state, url: url, identifier: identifier])

        if attempt.state == :running do
          maybe_complete_attempt(attempt, project, patch)
        end

      [] ->
        :ok
    end
  end

  def do_handle_cast({:cancel, patch_id}, project_id) do
    patch = Repo.get!(Patch, patch_id)
    ^project_id = patch.project_id

    case Repo.all(Attempt.all_for_patch(patch_id, :incomplete)) do
      [] ->
        :ok

      [attempt | _] ->
        attempt
        |> Attempt.changeset_state(%{state: :canceled})
        |> Repo.update!()
    end
  end

  def handle_info(:poll_once, project_id) do
    Repo.transaction(fn -> poll_(project_id) end)
    {:noreply, project_id}
  end

  def handle_info(:poll, project_id) do
    case Repo.transaction(fn -> poll_(project_id) end) do
      {:ok, :stop} ->
        {:stop, :normal, project_id}

      {:ok, :again} ->
        Process.send_after(self(), :poll, @poll_period)
        {:noreply, project_id}
    end
  end

  # Private implementation details

  defp poll_(project_id) do
    project = Repo.get(Project, project_id)

    incomplete =
      project_id
      |> Attempt.all_for_project(:running)
      |> Repo.all()

    incomplete
    |> Enum.filter(&Attempt.next_poll_is_past(&1, project))
    |> Enum.each(&poll_attempt(&1, project))

    if Enum.empty?(incomplete) do
      :stop
    else
      :again
    end
  end

  defp maybe_start_attempt(attempt, project) do
    case Repo.all(Attempt.all_for_project(project.id, :running)) do
      [] -> start_attempt(attempt, project)
      [_attempt | _] -> :ok
    end
  end

  defp start_attempt(attempt, project) do
    attempt =
      attempt
      |> Repo.preload([:patch])

    stmp = "#{project.trying_branch}.tmp"
    repo_conn = get_repo_conn(project)

    base =
      GitHub.get_branch!(
        repo_conn,
        attempt.into_branch
      )

    patch = attempt.patch
    arguments = attempt.arguments

    GitHub.synthesize_commit!(
      repo_conn,
      %{
        branch: stmp,
        tree: base.tree,
        parents: [base.commit],
        commit_message: "[ci skip][skip ci][skip netlify]",
        committer: nil
      }
    )

    merged =
      GitHub.merge_branch!(
        repo_conn,
        %{
          from: patch.commit,
          to: stmp,
          commit_message: "[ci skip][skip ci][skip netlify] -bors-staging-tmp-#{patch.pr_xref}"
        }
      )

    case merged do
      :conflict ->
        send_message(repo_conn, patch, {:conflict, :failed})

        attempt
        |> Attempt.changeset(%{state: :error})
        |> Repo.update!()

      _ ->
        toml =
          Batcher.GetBorsToml.get(
            repo_conn,
            stmp
          )

        case toml do
          {:ok, toml} ->
            commit =
              GitHub.synthesize_commit!(
                repo_conn,
                %{
                  branch: project.trying_branch,
                  tree: merged.tree,
                  parents: [base.commit, patch.commit],
                  commit_message: "Try \##{patch.pr_xref}:#{arguments}",
                  committer: toml.committer
                }
              )

            state = setup_statuses(attempt, toml)
            now = DateTime.to_unix(DateTime.utc_now(), :second)

            attempt
            |> Attempt.changeset(%{
              state: state,
              commit: commit,
              last_polled: now
            })
            |> Repo.update!()

          {:error, message} ->
            setup_statuses_error(
              repo_conn,
              attempt,
              patch,
              message
            )

            :error
        end
    end

    GitHub.delete_branch!(repo_conn, stmp)
  end

  defp setup_statuses(attempt, toml) do
    toml.status
    |> Enum.map(
      &%AttemptStatus{
        attempt_id: attempt.id,
        identifier: &1,
        url: nil,
        state: :running
      }
    )
    |> Enum.each(&Repo.insert!/1)

    now = DateTime.to_unix(DateTime.utc_now(), :second)

    attempt
    |> Attempt.changeset(%{timeout_at: now + toml.timeout_sec})
    |> Repo.update!()

    :running
  end

  defp setup_statuses_error(repo_conn, attempt, patch, message) do
    message = Batcher.Message.generate_bors_toml_error(message)

    attempt
    |> Attempt.changeset(%{state: :error})
    |> Repo.update!()

    send_message(repo_conn, patch, {:config, message})
  end

  defp poll_attempt(attempt, project) do
    patch = Repo.get!(Patch, attempt.patch_id)
    now = DateTime.to_unix(DateTime.utc_now(), :second)

    if attempt.timeout_at < now do
      timeout_attempt(attempt, project, patch)
    else
      project
      |> get_repo_conn()
      |> GitHub.get_commit_status!(attempt.commit)
      |> Enum.each(fn {identifier, state} ->
        attempt.id
        |> AttemptStatus.get_for_attempt(identifier)
        |> Repo.update_all(set: [state: state, identifier: identifier])
      end)

      maybe_complete_attempt(attempt, project, patch)
    end
  end

  defp maybe_complete_attempt(attempt, project, patch) do
    statuses = Repo.all(AttemptStatus.all_for_attempt(attempt.id))
    state = Batcher.State.summary_database_statuses(statuses)
    maybe_complete_attempt(state, project, patch, statuses)
    now = DateTime.to_unix(DateTime.utc_now(), :second)

    attempt
    |> Attempt.changeset(%{state: state, last_polled: now})
    |> Repo.update!()

    maybe_start_next_attempt(state, project)
  end

  defp maybe_complete_attempt(:ok, project, patch, statuses) do
    repo_conn = get_repo_conn(project)
    send_message(repo_conn, patch, {:succeeded, statuses})
  end

  defp maybe_complete_attempt(:error, project, patch, statuses) do
    repo_conn = get_repo_conn(project)

    erred =
      Enum.filter(
        statuses,
        &(&1.state == :error)
      )

    send_message(repo_conn, patch, {:failed, erred})
  end

  defp maybe_complete_attempt(:running, _project, _patch, _statuses) do
    :ok
  end

  defp maybe_start_next_attempt(:running, _project) do
    :ok
  end

  defp maybe_start_next_attempt(_state, project) do
    case Repo.all(Attempt.all_for_project(project.id, :waiting)) do
      [] ->
        :ok

      [attempt | _] ->
        maybe_start_attempt(attempt, project)
    end
  end

  defp timeout_attempt(attempt, project, patch) do
    project
    |> get_repo_conn()
    |> send_message(patch, {:timeout, :failed})

    attempt
    |> Attempt.changeset(%{state: :error})
    |> Repo.update!()
  end

  defp send_message(repo_conn, patch, message) do
    body = Batcher.Message.generate_message(message)

    GitHub.post_comment!(
      repo_conn,
      patch.pr_xref,
      "## try\n\n#{body}"
    )
  end

  @spec get_repo_conn(%Project{}) :: {{:installation, number}, number}
  defp get_repo_conn(project) do
    Project.installation_connection(project.repo_xref, Repo)
  end
end
