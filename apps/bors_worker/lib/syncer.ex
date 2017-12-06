defmodule BorsNG.Worker.Syncer do
  @moduledoc """
  A background task that pulls a full list of opened pull requests from a repo.
  Patches that don't come up get closed,
  and patches that don't exist get created.
  """

  alias BorsNG.Worker.Syncer
  alias BorsNG.Database.LinkUserProject
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.Database.User
  alias BorsNG.GitHub

  require Logger

  def start_synchronize_project(project_id) do
    {:ok, _} = Task.Supervisor.start_child(
      Syncer.Supervisor,
      fn -> synchronize_project(project_id) end)
  end

  def synchronize_project(project_id) do
    {:ok, _} = Registry.register(Syncer.Registry, project_id, {})
    conn = Project.installation_project_connection(project_id, Repo)
    open_patches = Repo.all(Patch.all_for_project(project_id, :open))
    open_prs = GitHub.get_open_prs!(conn)
    deltas = synchronize_patches(open_patches, open_prs)
    Enum.each(deltas, &do_synchronize!(project_id, &1))
    sync_admins_as_reviewers(conn, project_id)
    Project.ping!(project_id)
  end

  def sync_admins_as_reviewers(repo_conn, project_id) do
    case GitHub.get_admins_by_repo(repo_conn) do
      {:ok, admins} ->
        Enum.each(admins, fn user ->
          user = Syncer.sync_user(user)
          existing_link = Repo.get_by(LinkUserProject, user_id: user.id, project_id: project_id)
          if is_nil existing_link do
            link = %LinkUserProject{user_id: user.id, project_id: project_id}
            Repo.insert!(link)
          end
          :ok
        end)
      error ->
        Logger.warn(["Syncer: Error pulling repo admins: ", error])
    end
  end

  @doc """
  Returns a list of all patches that should be synchronized.

  Note: This will return a list of all opened pull requests,
  as well as a list of patches that should be closed.
  It does not perform any filtering on open PRs, because those
  still need to have their metadata synced.
  """
  @spec synchronize_patches([%Patch{}], [%GitHub.Pr{}]) ::
    [{:open, %GitHub.Pr{}} | {:close, %Patch{}}]
  def synchronize_patches(open_patches, open_prs) do
    open_prs_map = open_prs
    |> Enum.map(&{&1.number, &1})
    |> Map.new()
    closings = open_patches
    |> Enum.filter(fn %{pr_xref: pr_xref} ->
      not Map.has_key?(open_prs_map, pr_xref) end)
    |> Enum.map(&{:close, &1})
    openings = Enum.map(open_prs, &{:open, &1})
    openings ++ closings
  end

  def do_synchronize!(project_id, {:open, pr}) do
    sync_patch(project_id, pr)
  end

  def do_synchronize!(_project_id, {:close, patch}) do
    patch
    |> Patch.changeset(%{open: false})
    |> Repo.update!()
  end

  @spec sync_patch(integer, GitHub.Pr.t) :: Patch.t
  def sync_patch(project_id, pr) do
    number = pr.number
    author = sync_user(pr.user)
    data = %{
      project_id: project_id,
      into_branch: pr.base_ref,
      pr_xref: number,
      title: pr.title,
      body: pr.body,
      commit: pr.head_sha,
      author_id: author.id,
      open: pr.state == :open,
      author: author,
    }
    case Repo.get_by(Patch, project_id: project_id, pr_xref: number) do
      nil -> Repo.insert!(struct(Patch, data))
      patch ->
        patch
        |> Patch.changeset(data)
        |> Repo.update!()
    end
  end

  @spec sync_user(GitHub.User.t) :: %User{}
  def sync_user(gh_user) do
    case Repo.get_by(User, user_xref: gh_user.id) do
      nil -> Repo.insert!(%User{
        user_xref: gh_user.id,
        login: gh_user.login})
      user ->
        if user.login != gh_user.login do
          user
          |> User.changeset(%{login: gh_user.login})
          |> Repo.update!()
        else
          user
        end
    end
  end

  @doc """
  Wait for synchronization to finish by hot-spinning.
  Used in test cases.
  """
  def wait_hot_spin(project_id) do
    case Registry.lookup(Syncer.Registry, project_id) do
      [{_, _}] -> wait_hot_spin(project_id)
      _ -> :ok
    end
  end
end
