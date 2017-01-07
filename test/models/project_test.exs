defmodule Aelita2.ProjectTest do
  use Aelita2.ModelCase

  alias Aelita2.Installation
  alias Aelita2.Project
  alias Aelita2.User
  alias Aelita2.LinkUserProject

  setup do
    installation = Repo.insert!(%Installation{
      installation_xref: 31,
      })
    {:ok, installation: installation}
  end

  test "grab project by user", %{installation: installation} do
    project = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      })
    user = Repo.insert!(%User{
      login: "X",
      })
    Repo.insert!(%LinkUserProject{user: user, project: project})
    [project_x] = Repo.all(Project.by_owner(user.id))
    assert project_x.id == project.id
  end

  test "avoid project by other user", %{installation: installation} do
    project = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      })
    user = Repo.insert!(%User{
      login: "X",
      })
    user2 = Repo.insert!(%User{
      login: "Y",
      })
    Repo.insert!(%LinkUserProject{user: user, project: project})
    res = Repo.all(Project.by_owner(user2.id))
    assert res == []
  end

  test "avoid other project", %{installation: installation} do
    project = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      })
    _project2 = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 14,
      name: "example/project2",
      })
    user = Repo.insert!(%User{
      login: "X",
      })
    Repo.insert!(%LinkUserProject{user: user, project: project})
    [project_x] = Repo.all(Project.by_owner(user.id))
    assert project_x.id == project.id
  end
end
