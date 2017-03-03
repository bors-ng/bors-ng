defmodule BorsNG.SyncerTest do
  use BorsNG.ConnCase

  alias BorsNG.GitHub
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Syncer

  setup do
    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      master_branch: "master",
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
      open: false}
    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by! Patch, pr_xref: 1, project_id: proj.id
    assert p1.title == "Test PR"
    assert p1.open
    p2 = Repo.get_by! Patch, pr_xref: 2, project_id: proj.id
    assert p2.title == "Test PR X"
    assert p2.open
  end

  test "close a patche", %{proj: proj} do
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
    Repo.insert! %Patch{project_id: proj.id, pr_xref: 1, title: "Test PR"}
    Syncer.synchronize_project(proj.id)
    p1 = Repo.get_by! Patch, pr_xref: 1, project_id: proj.id
    assert p1.title == "Test PR"
    refute p1.open
    p2 = Repo.get_by! Patch, pr_xref: 2, project_id: proj.id
    assert p2.title == "Test PR X"
    assert p2.open
  end
end
