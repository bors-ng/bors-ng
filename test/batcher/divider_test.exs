defmodule BorsNG.Worker.Batcher.DividerTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.Worker.Batcher.Divider
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub.Pr
  alias BorsNG.GitHub

  import Ecto.Query

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

    batch =
      %Batch{
        project_id: proj.id,
        state: :running,
        into_branch: "master"
      }
      |> Repo.insert!()

    # fake the preloading of our test records
    batch = %Batch{batch | project: proj}

    patch1 =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "N",
        into_branch: "master"
      }
      |> Repo.insert!()

    patch2 =
      %Patch{
        project_id: proj.id,
        pr_xref: 2,
        commit: "N",
        into_branch: "master"
      }
      |> Repo.insert!()

    patch3 =
      %Patch{
        project_id: proj.id,
        pr_xref: 3,
        commit: "N",
        into_branch: "master"
      }
      |> Repo.insert!()

    patch4 =
      %Patch{
        project_id: proj.id,
        pr_xref: 4,
        commit: "N",
        into_branch: "master"
      }
      |> Repo.insert!()

    {:ok,
     inst: inst,
     proj: proj,
     batch: batch,
     patch1: patch1,
     patch2: patch2,
     patch3: patch3,
     patch4: patch4}
  end

  defp create_link(patch, batch) do
    link =
      %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id, reviewer: "some_user"}
      |> Repo.insert!()

    # manually preload
    %LinkPatchBatch{link | patch: patch}
  end

  describe "split_batch" do
    test "a batch containing one patch", %{proj: proj, batch: batch, patch1: patch} do
      link = create_link(patch, batch)

      result = Divider.split_batch([link], batch)

      assert result == :failed
      batches = Repo.all(Batch, project_id: proj.id)
      assert Enum.count(batches) == 1
    end

    test "a batch containing many patches", %{
      proj: proj,
      batch: batch,
      patch1: patch1,
      patch2: patch2,
      patch3: patch3,
      patch4: patch4
    } do
      link1 = create_link(patch1, batch)
      link2 = create_link(patch2, batch)
      link3 = create_link(patch3, batch)
      link4 = create_link(patch4, batch)

      result = Divider.split_batch([link1, link2, link3, link4], batch)

      assert result == :retrying

      [original_batch, new_batch1, new_batch2] =
        Repo.all(from(b in Batch, where: b.project_id == ^proj.id, order_by: [asc: b.id]))

      assert batch.id == original_batch.id

      links_for_new_batch1 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch1.id))

      assert Enum.map(links_for_new_batch1, & &1.patch_id) == [patch1.id, patch2.id]

      links_for_new_batch2 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch2.id))

      assert Enum.map(links_for_new_batch2, & &1.patch_id) == [patch3.id, patch4.id]
    end
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
              mergeable: false
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}
            ]
          }
        },
        :merge_conflict => 0
      })

      link = create_link(patch, batch)

      result = Divider.split_batch_with_conflicts([link], batch)

      assert result == :failed
      batches = Repo.all(Batch, project_id: proj.id)
      assert Enum.count(batches) == 1
    end

    test "multiple PRs that conflicts with master are retried individually", %{
      proj: proj,
      batch: batch,
      patch1: patch1,
      patch2: patch2
    } do
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
              mergeable: false
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
              mergeable: false
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}
            ],
            2 => [
              %GitHub.Commit{sha: "5678", author_name: "a", author_email: "e"}
            ]
          }
        },
        :merge_conflict => 0
      })

      link1 = create_link(patch1, batch)
      link2 = create_link(patch2, batch)

      result = Divider.split_batch_with_conflicts([link1, link2], batch)

      assert result == :retrying

      [original_batch, new_batch1, new_batch2] =
        Repo.all(from(b in Batch, where: b.project_id == ^proj.id, order_by: [asc: b.id]))

      assert batch.id == original_batch.id

      links_for_new_batch1 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch1.id))

      assert Enum.map(links_for_new_batch1, & &1.patch_id) == [patch1.id]

      links_for_new_batch2 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch2.id))

      assert Enum.map(links_for_new_batch2, & &1.patch_id) == [patch2.id]
    end

    test "multiple PRs without conflicts with master are retried via a bisect", %{
      proj: proj,
      batch: batch,
      patch1: patch1,
      patch2: patch2,
      patch3: patch3,
      patch4: patch4
    } do
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
              mergeable: true
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
              mergeable: true
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
              mergeable: true
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
              mergeable: true
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "0001", author_name: "a", author_email: "e"}
            ],
            2 => [
              %GitHub.Commit{sha: "0002", author_name: "a", author_email: "e"}
            ],
            3 => [
              %GitHub.Commit{sha: "0003", author_name: "a", author_email: "e"}
            ],
            4 => [
              %GitHub.Commit{sha: "0004", author_name: "a", author_email: "e"}
            ]
          }
        },
        :merge_conflict => 0
      })

      link1 = create_link(patch1, batch)
      link2 = create_link(patch2, batch)
      link3 = create_link(patch3, batch)
      link4 = create_link(patch4, batch)

      result = Divider.split_batch_with_conflicts([link1, link2, link3, link4], batch)

      assert result == :retrying

      [original_batch, new_batch1, new_batch2] =
        Repo.all(from(b in Batch, where: b.project_id == ^proj.id, order_by: [asc: b.id]))

      assert batch.id == original_batch.id

      links_for_new_batch1 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch1.id))

      assert Enum.map(links_for_new_batch1, & &1.patch_id) == [patch1.id, patch2.id]

      links_for_new_batch2 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch2.id))

      assert Enum.map(links_for_new_batch2, & &1.patch_id) == [patch3.id, patch4.id]
    end

    test "multiple PRs with and without conflicts with master", %{
      proj: proj,
      batch: batch,
      patch1: patch1,
      patch2: patch2,
      patch3: patch3,
      patch4: patch4
    } do
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
              mergeable: false
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
              mergeable: false
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
              mergeable: true
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
              mergeable: true
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "0001", author_name: "a", author_email: "e"}
            ],
            2 => [
              %GitHub.Commit{sha: "0002", author_name: "a", author_email: "e"}
            ],
            3 => [
              %GitHub.Commit{sha: "0003", author_name: "a", author_email: "e"}
            ],
            4 => [
              %GitHub.Commit{sha: "0004", author_name: "a", author_email: "e"}
            ]
          }
        },
        :merge_conflict => 0
      })

      link1 = create_link(patch1, batch)
      link2 = create_link(patch2, batch)
      link3 = create_link(patch3, batch)
      link4 = create_link(patch4, batch)

      result = Divider.split_batch_with_conflicts([link1, link2, link3, link4], batch)

      assert result == :retrying

      [original_batch, new_batch1, new_batch2, new_batch3] =
        Repo.all(from(b in Batch, where: b.project_id == ^proj.id, order_by: [asc: b.id]))

      assert batch.id == original_batch.id

      links_for_new_batch1 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch1.id))

      assert Enum.map(links_for_new_batch1, & &1.patch_id) == [patch1.id]

      links_for_new_batch2 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch2.id))

      assert Enum.map(links_for_new_batch2, & &1.patch_id) == [patch2.id]

      links_for_new_batch3 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch3.id))

      assert Enum.map(links_for_new_batch3, & &1.patch_id) == [patch3.id, patch4.id]
    end

    test "single PR that with unknown mergeable value is retried", %{
      proj: proj,
      batch: batch,
      patch1: patch
    } do
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
              mergeable: nil
            }
          },
          files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
          pr_commits: %{
            1 => [
              %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}
            ]
          }
        },
        :merge_conflict => 0
      })

      link = create_link(patch, batch)

      result = Divider.split_batch_with_conflicts([link], batch)

      assert result == :retrying

      [original_batch, new_batch1] =
        Repo.all(from(b in Batch, where: b.project_id == ^proj.id, order_by: [asc: b.id]))

      assert batch.id == original_batch.id

      links_for_new_batch1 =
        Repo.all(from(l in LinkPatchBatch, where: l.batch_id == ^new_batch1.id))

      assert Enum.map(links_for_new_batch1, & &1.patch_id) == [patch.id]
    end
  end

  describe "clone_batch" do
    test "creates a new batch with same links", %{
      proj: proj,
      batch: batch,
      patch1: patch1,
      patch2: patch2
    } do
      link1 = create_link(patch1, batch)
      link2 = create_link(patch2, batch)

      result = Divider.clone_batch([link1, link2], proj.id, "some-cloned-branch")

      assert result.id != batch.id
      assert result.project_id == proj.id
      assert result.into_branch == "some-cloned-branch"

      [original, cloned] =
        Repo.all(
          from(b in Batch,
            where: b.project_id == ^proj.id,
            order_by: [asc: b.id],
            preload: [:patches]
          )
        )

      assert original.id == batch.id
      assert cloned.id == result.id

      assert Enum.count(cloned.patches) == 2
      assert Enum.map(cloned.patches, & &1.patch_id) == [patch1.id, patch2.id]
      assert Enum.map(cloned.patches, & &1.reviewer) == ["some_user", "some_user"]

      original_link_ids = [link1.id, link2.id] |> Enum.sort()
      assert Enum.map(cloned.patches, & &1.id) |> Enum.sort() != original_link_ids

      Enum.each(cloned.patches, fn cloned_link ->
        assert Enum.member?(original_link_ids, cloned_link.id) == false
      end)
    end
  end
end
