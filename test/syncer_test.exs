import Ecto
import Ecto.Query

defmodule BorsNG.Worker.SyncerTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.GitHub
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Worker.Syncer

  setup do
    inst =
      %Installation{installation_xref: 91}
      |> Repo.insert!()

    proj =
      %Project{
        installation_id: inst.id,
        repo_xref: 14,
        staging_branch: "staging"
      }
      |> Repo.insert!()

    {:ok,
     inst: inst, proj: proj, proj_conn: {{:installation, inst.installation_xref}, proj.repo_xref}}
  end

  test "add and open patches", %{proj: proj, proj_conn: proj_conn} do
    GitHub.ServerMock.put_state(%{
      proj_conn => %{
        pulls: %{
          1 => %GitHub.Pr{
            number: 1,
            title: "Test PR",
            body: "test pr body",
            state: :open,
            base_ref: "master",
            head_sha: "HHH",
            user: %GitHub.User{
              login: "maya",
              id: 1,
              avatar_url: "whatevs"
            }
          },
          2 => %GitHub.Pr{
            number: 2,
            title: "Test PR X",
            body: "test pr body",
            state: :open,
            base_ref: "master",
            head_sha: "HHH",
            user: %GitHub.User{
              login: "maya",
              id: 1,
              avatar_url: "whatevs"
            }
          }
        },
        collaborators: []
      }
    })

    Repo.insert!(%Patch{
      project_id: proj.id,
      pr_xref: 1,
      title: "Test PR",
      into_branch: "master",
      open: false
    })

    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by!(Patch, pr_xref: 1, project_id: proj.id)
    assert p1.title == "Test PR"
    assert p1.open
    p2 = Repo.get_by!(Patch, pr_xref: 2, project_id: proj.id)
    assert p2.title == "Test PR X"
    assert p2.open
  end

  test "close a patch", %{proj: proj, proj_conn: proj_conn} do
    GitHub.ServerMock.put_state(%{
      proj_conn => %{
        pulls: %{
          1 => %GitHub.Pr{
            number: 1,
            title: "Test PR",
            body: "test pr body",
            state: :closed,
            base_ref: "master",
            head_sha: "HHH",
            user: %GitHub.User{
              login: "maya",
              id: 1,
              avatar_url: "whatevs"
            }
          },
          2 => %GitHub.Pr{
            number: 2,
            title: "Test PR X",
            body: "test pr body",
            state: :open,
            base_ref: "master",
            head_sha: "HHH",
            user: %GitHub.User{
              login: "maya",
              id: 1,
              avatar_url: "whatevs"
            }
          }
        },
        collaborators: []
      }
    })

    %Patch{
      project_id: proj.id,
      pr_xref: 1,
      title: "Test PR",
      into_branch: "master"
    }
    |> Repo.insert!()

    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by!(Patch, pr_xref: 1, project_id: proj.id)
    assert p1.title == "Test PR"
    refute p1.open
    p2 = Repo.get_by!(Patch, pr_xref: 2, project_id: proj.id)
    assert p2.title == "Test PR X"
    assert p2.into_branch == "master"
    assert p2.open
  end

  test "update commit on changed patch", %{proj: proj, proj_conn: proj_conn} do
    GitHub.ServerMock.put_state(%{
      proj_conn => %{
        pulls: %{
          1 => %GitHub.Pr{
            number: 1,
            title: "Test PR",
            body: "test pr body",
            state: :open,
            base_ref: "master",
            head_sha: "B",
            user: %GitHub.User{
              login: "maya",
              id: 1,
              avatar_url: "whatevs"
            }
          }
        },
        collaborators: []
      }
    })

    Repo.insert!(%Patch{
      project_id: proj.id,
      pr_xref: 1,
      title: "Test PR",
      into_branch: "master",
      commit: "A",
      open: true
    })

    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by!(Patch, pr_xref: 1, project_id: proj.id)
    assert p1.commit == "B"
    assert p1.open
  end

  test "synchronize collaborators with correct permissions",
       %{proj: proj, proj_conn: proj_conn} do
    # Set up some Github users with different permissions and previous existence
    # state
    old_admin = %GitHub.User{id: 1, login: "existing-admin"}
    new_admin = %GitHub.User{id: 2, login: "new-admin"}
    removed_admin = %GitHub.User{id: 3, login: "removed-admin"}
    old_pusher = %GitHub.User{id: 4, login: "existing-pusher"}
    new_pusher = %GitHub.User{id: 5, login: "new-pusher"}
    removed_pusher = %GitHub.User{id: 6, login: "removed-pusher"}
    puller = %GitHub.User{id: 7, login: "puller"}

    # Create the users that should exist
    saved_admins =
      [old_admin, removed_admin]
      |> Enum.map(&Syncer.sync_user/1)

    saved_pushers =
      [old_pusher, removed_pusher]
      |> Enum.map(&Syncer.sync_user/1)

    # Set up the pre-existing associations and settings
    proj =
      proj
      |> Repo.preload([:users, :members])
      |> Ecto.Changeset.change(%{
        auto_reviewer_required_perm: :admin,
        auto_member_required_perm: :push
      })
      |> Ecto.Changeset.put_assoc(:users, saved_admins)
      |> Ecto.Changeset.put_assoc(:members, saved_pushers)
      |> Repo.update!()

    # Set up the Github response
    GitHub.ServerMock.put_state(%{
      proj_conn => %{
        collaborators: [
          %{user: old_admin, perms: %{admin: true, push: true, pull: true}},
          %{user: new_admin, perms: %{admin: true, push: true, pull: true}},
          # removed admin is not present
          %{user: old_pusher, perms: %{admin: false, push: true, pull: true}},
          %{user: new_pusher, perms: %{admin: false, push: true, pull: true}},
          # removed pusher is not present
          %{user: puller, perms: %{admin: false, push: false, pull: true}}
        ]
      }
    })

    :ok = Syncer.synchronize_project_collaborators(proj_conn, proj.id)

    user_xrefs =
      Repo.all(
        from(u in assoc(proj, :users),
          select: u.user_xref
        )
      )

    member_xrefs =
      Repo.all(
        from(u in assoc(proj, :members),
          select: u.user_xref
        )
      )

    assert Enum.sort(user_xrefs) == Enum.sort([old_admin.id, new_admin.id])

    assert Enum.sort(member_xrefs) ==
             Enum.sort([old_admin.id, new_admin.id, old_pusher.id, new_pusher.id])
  end

  test "do not synchronize collaborators when it's turned off",
       %{proj: proj, proj_conn: proj_conn} do
    # Set up some Github users with different permissions and previous existence
    # state
    old_admin = %GitHub.User{id: 1, login: "existing-admin"}
    new_admin = %GitHub.User{id: 2, login: "new-admin"}
    removed_admin = %GitHub.User{id: 3, login: "removed-admin"}
    old_pusher = %GitHub.User{id: 4, login: "existing-pusher"}
    new_pusher = %GitHub.User{id: 5, login: "new-pusher"}
    removed_pusher = %GitHub.User{id: 6, login: "removed-pusher"}
    puller = %GitHub.User{id: 7, login: "puller"}

    # Create the users that should exist
    saved_admins =
      [old_admin, removed_admin]
      |> Enum.map(&Syncer.sync_user/1)

    saved_pushers =
      [old_pusher, removed_pusher]
      |> Enum.map(&Syncer.sync_user/1)

    # Set up the pre-existing associations and settings
    proj =
      proj
      |> Repo.preload([:users, :members])
      |> Ecto.Changeset.change(%{auto_reviewer_required_perm: nil, auto_member_required_perm: nil})
      |> Ecto.Changeset.put_assoc(:users, saved_admins)
      |> Ecto.Changeset.put_assoc(:members, saved_pushers)
      |> Repo.update!()

    # Set up the Github response
    GitHub.ServerMock.put_state(%{
      proj_conn => %{
        collaborators: [
          %{user: old_admin, perms: %{admin: true, push: true, pull: true}},
          %{user: new_admin, perms: %{admin: true, push: true, pull: true}},
          # removed admin is not present
          %{user: old_pusher, perms: %{admin: false, push: true, pull: true}},
          %{user: new_pusher, perms: %{admin: false, push: true, pull: true}},
          # removed pusher is not present
          %{user: puller, perms: %{admin: false, push: false, pull: true}}
        ]
      }
    })

    :ok = Syncer.synchronize_project_collaborators(proj_conn, proj.id)

    user_xrefs =
      Repo.all(
        from(u in assoc(proj, :users),
          select: u.user_xref
        )
      )

    member_xrefs =
      Repo.all(
        from(u in assoc(proj, :members),
          select: u.user_xref
        )
      )

    assert Enum.sort(user_xrefs) == Enum.sort([old_admin.id, removed_admin.id])

    assert Enum.sort(member_xrefs) ==
             Enum.sort([
               old_pusher.id,
               removed_pusher.id
             ])
  end
end
