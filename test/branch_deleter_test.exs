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

    %{proj: proj, inst: inst}
  end

  test "deletes by patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        commits: %{},
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
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    branches =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master"]
  end

  test "deletes by patch when squashing and merging", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        commits: %{},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => %Pr{
            number: 1,
            title: "[Merged by Bors] - Test",
            body: "Total Mess",
            state: :closed,
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
              use_squash_merge = true
            """
          },
          "update" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
              use_squash_merge = true
            """
          }
        }
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    branches =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master"]
  end

  test "don't delete patch if closed by other reason", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        commits: %{},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => %Pr{
            number: 1,
            title: "Test",
            body: "Total Mess",
            state: :closed,
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
              use_squash_merge = true
            """
          },
          "update" => %{
            ".github/bors.toml" => ~s"""
              status = [ "ci" ]
              delete_merged_branches = true
              use_squash_merge = true
            """
          }
        }
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    branches =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master", "update"]
  end

  test "reschedules fetch if pr is not merged", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        commits: %{},
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
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    assert_receive {:retry_delete, _patch, 1}

    branches =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master", "update"]
  end

  test "doesnt delete anything if toml arg not set", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo"},
        commits: %{},
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
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    branches =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master", "update"]
  end

  test "deletes by patch updating dependant PR base branch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo", "update2" => "bar"},
        commits: %{},
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
          },
          2 => %Pr{
            number: 2,
            title: "Depends on Test",
            body: "Mess",
            state: :open,
            base_ref: "update",
            head_sha: "00000002",
            head_ref: "update2",
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
              update_base_for_deletes = true
            """
          }
        }
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    installation =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})

    branches =
      installation
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master", "update2"]

    dependant_pr_base_ref =
      installation
      |> Map.get(:pulls)
      |> Map.get(2)
      |> Map.get(:base_ref)

    assert dependant_pr_base_ref == "master"
  end

  test "deletes by patch without updating dependant PR base branch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "update" => "foo", "update2" => "bar"},
        commits: %{},
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
          },
          2 => %Pr{
            number: 2,
            title: "Depends on Test",
            body: "Mess",
            state: :open,
            base_ref: "update",
            head_sha: "00000002",
            head_ref: "update2",
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
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "foo",
        into_branch: "master"
      }
      |> Repo.insert!()

    BranchDeleter.handle_cast({:delete, patch, 0}, :ok)

    installation =
      GitHub.ServerMock.get_state()
      |> Map.get({{:installation, 91}, 14})

    branches =
      installation
      |> Map.get(:branches)
      |> Map.keys()

    assert branches == ["master", "update2"]

    dependant_pr_base_ref =
      installation
      |> Map.get(:pulls)
      |> Map.get(2)
      |> Map.get(:base_ref)

    assert dependant_pr_base_ref == "update"
  end
end
