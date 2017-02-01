defmodule Aelita2.Syncer do
  @moduledoc """
  A background task that pulls a full list of opened pull requests from a repo.
  Patches that don't come up get closed,
  and patches that don't exist get created.
  """

  alias Aelita2.Repo
  alias Aelita2.GitHub
  alias Aelita2.Patch
  alias Aelita2.Project
  alias Aelita2.User

  def start_synchronize_project(project_id) do
    {:ok, _} = Task.Supervisor.start_child(
      Aelita2.Syncer.Supervisor,
      fn -> synchronize_project(project_id) end)
  end

  def synchronize_project(project_id) do
    {:ok, _} = Registry.register(Aelita2.Syncer.Registry, project_id, {})
    conn = Project.installation_project_connection(project_id, Repo)
    open_patches = Repo.all(Patch.all_for_project(project_id, :open))
    open_prs = GitHub.get_open_prs!(conn)
    deltas = synchronize_patches(open_patches, open_prs)
    Enum.each(deltas, &do_synchronize!(project_id, &1))
    Project.ping!(project_id)
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

  @spec sync_patch(integer, Aelita2.GitHub.Pr.t) :: Aelita2.Patch.t
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

  @spec sync_user(Aelita2.GitHub.User.t) :: %Aelita2.User{}
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
end
