defmodule BorsNG.Worker.Batcher.DividerTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.Worker.Batcher
  alias BorsNG.Worker.Batcher.Divider
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub.Pr
  alias BorsNG.Database.Status
  alias BorsNG.GitHub

  import Ecto.Query

  setup do
    inst = %Installation{installation_xref: 91}
           |> Repo.insert!()
    proj = %Project{
             installation_id: inst.id,
             repo_xref: 14,
             staging_branch: "staging"}
           |> Repo.insert!()
    batch = %Batch{
              project_id: proj.id,
              state: :running,
              into_branch: "master"}
            |> Repo.insert!()
    batch = %Batch{batch | project: proj} # fake the preloading of our test records
    patch1 = %Patch{
               project_id: proj.id,
               pr_xref: 1,
               commit: "N",
               into_branch: "master"}
             |> Repo.insert!()

    patch2 = %Patch{
               project_id: proj.id,
               pr_xref: 2,
               commit: "N",
               into_branch: "master"}
             |> Repo.insert!()

    patch3 = %Patch{
               project_id: proj.id,
               pr_xref: 3,
               commit: "N",
               into_branch: "master"}
             |> Repo.insert!()

    patch4 = %Patch{
               project_id: proj.id,
               pr_xref: 4,
               commit: "N",
               into_branch: "master"}
             |> Repo.insert!()
    {:ok, inst: inst, proj: proj, batch: batch, patch1: patch1, patch2: patch2, patch3: patch3, patch4: patch4}
  end

  describe "split_batch_with_conflicts" do

    test "single PR that conflicts with master fails", %{proj: proj, batch: batch, patch1: patch} do
      # Projects are created with a "waiting" state
      GitHub.ServerMock.put_state(%{
        {{:installation, 91}, 14} => %{
          branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
          commits: %{},
          comments: %{1 => []},
          statuses: %{"iniN" => %{}},
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
              merged: false,
              mergeable: false,
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{1 => [
                          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
          ]},
        },
        :merge_conflict => 0,
      })

      link = %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link = %LinkPatchBatch{link | patch: patch} # fake the preloading of our test records


      result = Divider.split_batch_with_conflicts([link], batch)


      assert result == :failed
      batches = Repo.all Batch, project_id: proj.id
      assert (Enum.count batches) == 1
    end

    test "multiple PRs that conflicts with master are retried individually", %{proj: proj, batch: batch, patch1: patch1, patch2: patch2} do
      # Projects are created with a "waiting" state
      GitHub.ServerMock.put_state(%{
        {{:installation, 91}, 14} => %{
          branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
          commits: %{},
          comments: %{1 => [], 2 => []},
          statuses: %{"iniN" => %{}},
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
              merged: false,
              mergeable: false,
            },
            2 => %Pr{
              number: 1,
              title: "Test 2",
              body: "Mess 2",
              state: :open,
              base_ref: "master",
              head_sha: "00000002",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: false,
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
            ],
            2 => [
              %GitHub.Commit{sha: "5678", author_name: "a", author_email: "e"},
            ]},
        },
        :merge_conflict => 0,
      })

      link1 = %LinkPatchBatch{patch_id: patch1.id, batch_id: batch.id, reviewer: "some_user"}
             |> Repo.insert!()
      link1 = %LinkPatchBatch{link1 | patch: patch1} # fake the preloading of our test records

      link2 = %LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link2 = %LinkPatchBatch{link2 | patch: patch2} # fake the preloading of our test records


      result = Divider.split_batch_with_conflicts([link1, link2], batch)


      assert result == :retrying
      batches = Repo.all Batch, project_id: proj.id
      assert (Enum.count batches) == 3 # original, plus new batch for patch1, plus new batch for patch2

      # TODO: check batch 2 contains link1
      # TODO: check batch 3 contains link2
    end

    test "multiple PRs without conflicts with master are retried via a bisect", %{proj: proj, batch: batch, patch1: patch1, patch2: patch2, patch3: patch3, patch4: patch4} do
      GitHub.ServerMock.put_state(%{
        {{:installation, 91}, 14} => %{
          branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
          commits: %{},
          comments: %{1 => [], 2 => [], 3 => [], 4 => []},
          statuses: %{"iniN" => %{}},
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
              merged: false,
              mergeable: true,
            },
            2 => %Pr{
              number: 1,
              title: "Test 2",
              body: "Mess 2",
              state: :open,
              base_ref: "master",
              head_sha: "00000002",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: true,
            },
            3 => %Pr{
              number: 1,
              title: "Test 3",
              body: "Mess 3",
              state: :open,
              base_ref: "master",
              head_sha: "00000003",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: true,
            },
            4 => %Pr{
              number: 1,
              title: "Test 4",
              body: "Mess 4",
              state: :open,
              base_ref: "master",
              head_sha: "00000004",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: true,
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "0001", author_name: "a", author_email: "e"},
            ],
            2 => [
              %GitHub.Commit{sha: "0002", author_name: "a", author_email: "e"},
            ],
            3 => [
              %GitHub.Commit{sha: "0003", author_name: "a", author_email: "e"},
            ],
            4 => [
              %GitHub.Commit{sha: "0004", author_name: "a", author_email: "e"},
            ]},
        },
        :merge_conflict => 0,
      })

      link1 = %LinkPatchBatch{patch_id: patch1.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link1 = %LinkPatchBatch{link1 | patch: patch1} # fake the preloading of our test records

      link2 = %LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link2 = %LinkPatchBatch{link2 | patch: patch2} # fake the preloading of our test records

      link3 = %LinkPatchBatch{patch_id: patch3.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link3 = %LinkPatchBatch{link3 | patch: patch3} # fake the preloading of our test records

      link4 = %LinkPatchBatch{patch_id: patch4.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link4 = %LinkPatchBatch{link4 | patch: patch4} # fake the preloading of our test records


      result = Divider.split_batch_with_conflicts([link1, link2, link3, link4], batch)


      assert result == :retrying
      batches = Repo.all Batch, project_id: proj.id
      assert (Enum.count batches) == 3 # original, plus new batch for patch1, plus new batch for patch2
      # TODO: check batch 2 contains link1 and link2
      # TODO: check batch 3 contains link3 and link4
    end

    test "multiple PRs with and without conflicts with master", %{proj: proj, batch: batch, patch1: patch1, patch2: patch2, patch3: patch3, patch4: patch4} do
      GitHub.ServerMock.put_state(%{
        {{:installation, 91}, 14} => %{
          branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
          commits: %{},
          comments: %{1 => [], 2 => [], 3 => [], 4 => []},
          statuses: %{"iniN" => %{}},
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
              merged: false,
              mergeable: false,
            },
            2 => %Pr{
              number: 1,
              title: "Test 2",
              body: "Mess 2",
              state: :open,
              base_ref: "master",
              head_sha: "00000002",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: false,
            },
            3 => %Pr{
              number: 1,
              title: "Test 3",
              body: "Mess 3",
              state: :open,
              base_ref: "master",
              head_sha: "00000003",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: true,
            },
            4 => %Pr{
              number: 1,
              title: "Test 4",
              body: "Mess 4",
              state: :open,
              base_ref: "master",
              head_sha: "00000004",
              head_ref: "update",
              base_repo_id: 14,
              head_repo_id: 14,
              merged: false,
              mergeable: true,
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "0001", author_name: "a", author_email: "e"},
            ],
            2 => [
              %GitHub.Commit{sha: "0002", author_name: "a", author_email: "e"},
            ],
            3 => [
              %GitHub.Commit{sha: "0003", author_name: "a", author_email: "e"},
            ],
            4 => [
              %GitHub.Commit{sha: "0004", author_name: "a", author_email: "e"},
            ]},
        },
        :merge_conflict => 0,
      })

      link1 = %LinkPatchBatch{patch_id: patch1.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link1 = %LinkPatchBatch{link1 | patch: patch1} # fake the preloading of our test records

      link2 = %LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link2 = %LinkPatchBatch{link2 | patch: patch2} # fake the preloading of our test records

      link3 = %LinkPatchBatch{patch_id: patch3.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link3 = %LinkPatchBatch{link3 | patch: patch3} # fake the preloading of our test records

      link4 = %LinkPatchBatch{patch_id: patch4.id, batch_id: batch.id, reviewer: "some_user"}
              |> Repo.insert!()
      link4 = %LinkPatchBatch{link4 | patch: patch4} # fake the preloading of our test records


      result = Divider.split_batch_with_conflicts([link1, link2, link3, link4], batch)


      assert result == :retrying
      batches = Repo.all Batch, project_id: proj.id
      assert (Enum.count batches) == 4 # original
      # TODO: check batch 2 contains link1
      # TODO: check batch 3 contains link2
      # TODO: check batch 4 contains link3 and link4
    end

    test "single PR that with unknown mergeable value is retried", %{proj: proj, batch: batch, patch1: patch} do
      # Projects are created with a "waiting" state
      GitHub.ServerMock.put_state(%{
        {{:installation, 91}, 14} => %{
          branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
          commits: %{},
          comments: %{1 => []},
          statuses: %{"iniN" => %{}},
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
              merged: false,
              mergeable: nil,
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{1 => [
                          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
          ]},
        },
        :merge_conflict => 0,
      })

      link = %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id, reviewer: "some_user"}
             |> Repo.insert!()
      link = %LinkPatchBatch{link | patch: patch} # fake the preloading of our test records


      result = Divider.split_batch_with_conflicts([link], batch)


      assert result == :retrying
      batches = Repo.all Batch, project_id: proj.id
      assert (Enum.count batches) == 2
      # TODO: assert batch 2 contains link1
    end

  end
end
