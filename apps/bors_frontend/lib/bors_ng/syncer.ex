defmodule BorsNG.Syncer do
  @moduledoc """
  A background task that pulls a full list of opened pull requests from a repo.
  Patches that don't come up get closed,
  and patches that don't exist get created.
  """

  alias BorsNG.Syncer
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.User
  alias BorsNG.GitHub

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
    BorsNG.ProjectPingChannel.ping!(project_id)
  end

  @spec synchronize_patches([%Patch{}], [%GitHub.Pr{}]) ::
    [{:open, %GitHub.Pr{}} | {:close, %Patch{}}]
  def synchronize_patches(open_patches, open_prs) do
    open_patches = open_patches
    |> Enum.map(&{&1.pr_xref, &1})
    |> Map.new()
    open_prs = open_prs
    |> Enum.map(&{&1.number, &1})
    |> Map.new()
    openings = open_prs
    |> Enum.filter(fn {pr_xref, _} ->
      not Map.has_key?(open_patches, pr_xref) end)
    |> Enum.map(fn {_, pr} ->
      {:open, pr} end)
    closings = open_patches
    |> Enum.filter(fn {pr_xref, _} ->
      not Map.has_key?(open_prs, pr_xref) end)
    |> Enum.map(fn {_, patch} ->
      {:close, patch} end)
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
    patch = case Repo.get_by(Patch, project_id: project_id, pr_xref: number) do
      nil -> Repo.insert!(%Patch{
        project_id: project_id,
        pr_xref: number,
        title: pr.title,
        body: pr.body,
        commit: pr.head_sha,
        author_id: author.id,
        open: pr.state == :open
      })
      patch ->
        if patch.open != (pr.state == :open) do
          patch
          |> Patch.changeset(%{open: pr.state == :open})
          |> Repo.update!()
        else
          patch
        end
    end
    %Patch{patch | author: author}
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
