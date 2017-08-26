defmodule BorsNG.Worker.SyncerTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.GitHub
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Worker.Syncer

  setup do
    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      staging_branch: "staging"}
    |> Repo.insert!()
    {:ok, inst: inst, proj: proj}
  end

  test "add and open patches", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
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
              avatar_url: "whatevs",
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
              avatar_url: "whatevs",
            }
          }
        }
      }})
    Repo.insert! %Patch{
      project_id: proj.id,
      pr_xref: 1,
      title: "Test PR",
      into_branch: "master",
      open: false}
    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by! Patch, pr_xref: 1, project_id: proj.id
    assert p1.title == "Test PR"
    assert p1.open
    p2 = Repo.get_by! Patch, pr_xref: 2, project_id: proj.id
    assert p2.title == "Test PR X"
    assert p2.open
  end

  test "close a patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
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
              avatar_url: "whatevs",
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
              avatar_url: "whatevs",
            }
          }
        }
      }})
    %Patch{
      project_id: proj.id,
      pr_xref: 1,
      title: "Test PR",
      into_branch: "master"}
    |> Repo.insert!()
    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by! Patch, pr_xref: 1, project_id: proj.id
    assert p1.title == "Test PR"
    refute p1.open
    p2 = Repo.get_by! Patch, pr_xref: 2, project_id: proj.id
    assert p2.title == "Test PR X"
    assert p2.into_branch == "master"
    assert p2.open
  end

  test "update commit on changed patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
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
              avatar_url: "whatevs",
            },
          },
        },
      }})
    Repo.insert! %Patch{
      project_id: proj.id,
      pr_xref: 1,
      title: "Test PR",
      into_branch: "master",
      commit: "A",
      open: true}
    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by! Patch, pr_xref: 1, project_id: proj.id
    assert p1.commit == "B"
    assert p1.open
  end
end
