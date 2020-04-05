defmodule BorsNG.Database.DashboardContextTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Batch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project
  alias BorsNG.Database.User
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.LinkUserProject
  alias BorsNG.Database.LinkMemberProject
  alias BorsNG.Database.Context.Dashboard

  setup do
    installation =
      Repo.insert!(%Installation{
        installation_xref: 31
      })

    project =
      Repo.insert!(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project"
      })

    {:ok, installation: installation, project: project}
  end

  test "grab project by user", %{project: project} do
    user =
      Repo.insert!(%User{
        login: "X"
      })

    Repo.insert!(%LinkUserProject{user: user, project: project})
    [project_x] = Dashboard.my_projects(user.id)
    assert project_x.id == project.id
  end

  test "avoid project by other user", %{project: project} do
    user =
      Repo.insert!(%User{
        login: "X"
      })

    user2 =
      Repo.insert!(%User{
        login: "Y"
      })

    Repo.insert!(%LinkUserProject{user: user, project: project})
    res = Dashboard.my_projects(user2.id)
    assert res == []
  end

  test "avoid other project", %{installation: installation, project: project} do
    project2 =
      Repo.insert!(%Project{
        installation_id: installation.id,
        repo_xref: 14,
        name: "example/project2"
      })

    user =
      Repo.insert!(%User{
        login: "X"
      })

    user2 =
      Repo.insert!(%User{
        login: "y"
      })

    Repo.insert!(%LinkUserProject{user: user, project: project})
    Repo.insert!(%LinkUserProject{user: user2, project: project2})
    [project_x] = Dashboard.my_projects(user.id)
    assert project_x.id == project.id
  end

  test "does not duplicate resultset when simultaneously member and reviewer", %{project: project} do
    user =
      Repo.insert!(%User{
        login: "X"
      })

    Repo.insert!(%LinkMemberProject{user: user, project: project})
    Repo.insert!(%LinkUserProject{user: user, project: project})
    projects = Dashboard.my_projects(user.id)
    assert Enum.count(projects) == 1
    [project_x] = projects
    assert project_x.id == project.id
  end

  test "returns both projects where member or where reviewer", context do
    project2 =
      Repo.insert!(%Project{
        installation_id: context.installation.id,
        repo_xref: 14,
        name: "example/project2"
      })

    user =
      Repo.insert!(%User{
        login: "X"
      })

    Repo.insert!(%LinkUserProject{user: user, project: context.project})
    Repo.insert!(%LinkMemberProject{user: user, project: project2})

    projects = Dashboard.my_projects(user.id)
    assert Enum.count(projects) == 2
    ids = Enum.map(projects, & &1.id)
    assert [context.project.id, project2.id] == Enum.sort(ids)
  end

  test "grab patches that a particular user has", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    patch2 =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 10,
        title: "T",
        body: "B",
        commit: "C"
      })

    Repo.insert!(%LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id})
    user = Repo.insert!(%User{})
    Repo.insert!(%LinkUserProject{user_id: user.id, project_id: project.id})
    [got_patch] = Dashboard.my_patches(user.id)
    assert got_patch.id == patch.id
  end
end
