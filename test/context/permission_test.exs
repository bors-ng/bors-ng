defmodule BorsNG.Database.Context.PermissionTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Context.Permission
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkUserProject
  alias BorsNG.Database.LinkMemberProject
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.User
  alias BorsNG.Database.UserPatchDelegation

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

    user =
      Repo.insert!(%User{
        login: "lilac"
      })

    patch =
      Repo.insert!(%Patch{
        project: project
      })

    {:ok, project: project, user: user, patch: patch}
  end

  test "user does not have permission by default", params do
    %{patch: patch, user: user} = params
    refute Permission.permission?(:reviewer, user, patch)
    refute Permission.permission?(:member, user, patch)
  end

  test "reviewers have permission", params do
    %{project: project, patch: patch, user: user} = params
    Repo.insert!(%LinkUserProject{user: user, project: project})
    assert Permission.permission?(:reviewer, user, patch)
    assert Permission.permission?(:member, user, patch)
  end

  test "delegated users have permission", params do
    %{patch: patch, user: user} = params
    Repo.insert!(%UserPatchDelegation{user: user, patch: patch})
    assert Permission.permission?(:reviewer, user, patch)
    assert Permission.permission?(:member, user, patch)
  end

  test "members have partial permission", params do
    %{project: project, patch: patch, user: user} = params
    Repo.insert!(%LinkMemberProject{user: user, project: project})
    refute Permission.permission?(:reviewer, user, patch)
    assert Permission.permission?(:member, user, patch)
  end
end
