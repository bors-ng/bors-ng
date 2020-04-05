defmodule BorsNG.Worker.BranchDeleter do
  @moduledoc """
  BranchDeleter controls merged branches removal
  if delete_merged_branches is true in bors.toml file.

  By default we wait for pull request "closed" event with pr merged flag set.
  Also since event arrival is not guaranteed we poll every 5 minutes and
  if pr is merged we delete pr head branch.
  """

  use GenServer
  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  # 1 minute between tries
  @retry_delay 60 * 1000

  # keep trying for one hour
  @retries 60

  # Public API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def delete(%Patch{} = patch) do
    GenServer.cast(__MODULE__, {:delete, patch, 0})
  end

  # Server callbacks

  def init(:ok) do
    {:ok, :ok}
  end

  def handle_cast({:delete, patch, attempt}, state) do
    patch = Repo.preload(patch, :project)
    conn = Project.installation_connection(patch.project.repo_xref, Repo)

    case GitHub.get_pr(conn, patch.pr_xref) do
      {:ok, %{merged: true} = pr} ->
        delete_branch(conn, pr)

      {:ok, %{state: :closed} = pr} ->
        delete_branch(conn, pr)

      {:ok, %{state: :open}} when attempt < @retries ->
        Process.send_after(
          self(),
          {:retry_delete, patch, attempt + 1},
          attempt_delay(attempt)
        )

      _ ->
        nil
    end

    {:noreply, state}
  end

  def handle_info({:retry_delete, patch, attempt}) do
    GenServer.cast(__MODULE__, {:delete, patch, attempt})
  end

  defp delete_branch(conn, pr) do
    pr_in_same_repo =
      pr.head_repo_id > 0 &&
        pr.head_repo_id == pr.base_repo_id

    toml_result = Batcher.GetBorsToml.get(conn, pr.head_ref)

    delete_merged_branches =
      case toml_result do
        {:ok, toml} -> toml.delete_merged_branches
        _ -> false
      end

    pr_closed = pr.state == :closed

    pr_squash_merged = String.starts_with?(pr.title, "[Merged by Bors] - ")

    if pr_in_same_repo && delete_merged_branches do
      cond do
        pr.merged ->
          GitHub.delete_branch!(conn, pr.head_ref)

        pr_closed && pr_squash_merged ->
          GitHub.delete_branch!(conn, pr.head_ref)

        true ->
          nil
      end
    end
  end

  defp attempt_delay(attempt) do
    @retry_delay * attempt
  end
end
