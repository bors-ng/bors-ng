defmodule BorsNG.Worker.BranchDeleterTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.Worker.BranchDeleter
  alias BorsNG.GitHub
  alias BorsNG.GitHub.Pr
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Repo

  setup do
    {:ok, deleter} = BranchDeleter.start_link()

    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      staging_branch: "staging"}
    |> Repo.insert!()

    %{deleter: deleter, proj: proj, inst: inst}
  end

  test "deletes by pull request" do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => %Pr{
            number: 1,
            title: "Test",
            body: "Mess",
            state: :open,
            base_ref: "master",
            head_sha: "00000001",
            head_ref: "update",
            base_repo_id: 14,
            head_repo_id: 14,
            merged: true
          }
        },
        files: %{
          "master" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
            """
          },
          "update" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
            """
          }
        }
      }})

    pr = %Pr{
      number: 1,
      title: "Test",
      body: "Mess",
      state: :open,
      base_ref: "master",
      head_sha: "00000001",
      head_ref: "update",
      base_repo_id: 14,
      head_repo_id: 14,
      merged: true
    }

    BranchDeleter.handle_cast({:delete, pr}, :ok)

    branches = GitHub.ServerMock.get_state()
    |> Map.get({{:installation, 91}, 14})
    |> Map.get(:branches)
    |> Map.keys
    assert branches == ["master"]
  end

  test "deletes by patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => %Pr{
            number: 1,
            title: "Test",
            body: "Mess",
            state: :open,
            base_ref: "master",
            head_sha: "00000001",
            head_ref: "update",
            base_repo_id: 14,
            head_repo_id: 14,
            merged: true
          }
        },
        files: %{
          "master" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
            """
          },
          "update" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
            """
          }
        }
      }})

    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "foo",
      into_branch: "master"}
    |> Repo.insert!()

    BranchDeleter.handle_cast({:delete_by_patch, patch, 0}, :ok)

    branches = GitHub.ServerMock.get_state()
    |> Map.get({{:installation, 91}, 14})
    |> Map.get(:branches)
    |> Map.keys
    assert branches == ["master"]
  end

  test "reschedules fetch if pr is not merged", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => %Pr{
            number: 1,
            title: "Test",
            body: "Mess",
            state: :open,
            base_ref: "master",
            head_sha: "00000001",
            head_ref: "update",
            base_repo_id: 14,
            head_repo_id: 14,
            merged: false
          }
        },
        files: %{
          "master" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
            """
          },
          "update" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
            """
          }
        }
      }})

    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "foo",
      into_branch: "master"}
    |> Repo.insert!()

    BranchDeleter.handle_cast({:delete_by_patch, patch, 0}, :ok)

    branches = GitHub.ServerMock.get_state()
    |> Map.get({{:installation, 91}, 14})
    |> Map.get(:branches)
    |> Map.keys
    assert branches == ["master", "update"]
  end

  test "doesnt delete anything if toml arg not set", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => %Pr{
            number: 1,
            title: "Test",
            body: "Mess",
            state: :open,
            base_ref: "master",
            head_sha: "00000001",
            head_ref: "update",
            base_repo_id: 14,
            head_repo_id: 14,
            merged: false
          }
        },
        files: %{
          "master" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = false
            """
          },
          "update" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = false
            """
          }
        }
      }})

    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "foo",
      into_branch: "master"}
    |> Repo.insert!()

    BranchDeleter.handle_cast({:delete_by_patch, patch, 0}, :ok)

    branches = GitHub.ServerMock.get_state()
    |> Map.get({{:installation, 91}, 14})
    |> Map.get(:branches)
    |> Map.keys
    assert branches == ["master", "update"]
  end
end
