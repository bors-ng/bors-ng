defmodule BorsNG.Database.ProjectTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project

  setup do
    installation =
      Repo.insert!(%Installation{
        installation_xref: 31
      })

    {:ok, installation: installation}
  end

  test "accept valid permission values", %{installation: installation} do
    {result, _} =
      Repo.insert(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project",
        auto_reviewer_required_perm: :admin,
        auto_member_required_perm: :admin
      })

    assert result == :ok

    {result, _} =
      Repo.insert(%Project{
        installation_id: installation.id,
        repo_xref: 14,
        name: "example/project2",
        auto_reviewer_required_perm: :push,
        auto_member_required_perm: :pull
      })

    assert result == :ok
  end

  test "accept nil permission values", %{installation: installation} do
    {result, _} =
      Repo.insert(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project",
        auto_reviewer_required_perm: nil,
        auto_member_required_perm: nil
      })

    assert result == :ok
  end

  test "reject invalid permission values", %{installation: installation} do
    assert_raise Ecto.ChangeError, fn ->
      Repo.insert!(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project",
        auto_reviewer_required_perm: :invalid,
        auto_member_required_perm: :invalid
      })
    end
  end
end
