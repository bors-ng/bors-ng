defmodule BorsNG.Database.ProjectTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project
  alias BorsNG.Database.User
  alias BorsNG.Database.LinkUserProject

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

  test "accept valid permission values", %{installation: installation} do
    {result, _} = Repo.insert(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      auto_reviewer_required_perm: :admin,
      auto_member_required_perm: :admin})
    assert result == :ok

    {result, _} = Repo.insert(%Project{
      installation_id: installation.id,
      repo_xref: 14,
      name: "example/project2",
      auto_reviewer_required_perm: :push,
      auto_member_required_perm: :pull})
    assert result == :ok
  end

  test "accept nil permission values", %{installation: installation} do
    {result, _} = Repo.insert(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      auto_reviewer_required_perm: nil,
      auto_member_required_perm: nil})
    assert result == :ok
  end

  test "reject invalid permission values", %{installation: installation} do
    assert_raise Ecto.ChangeError, fn ->
      Repo.insert!(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project",
        auto_reviewer_required_perm: :invalid,
        auto_member_required_perm: :invalid})
    end
  end
end
