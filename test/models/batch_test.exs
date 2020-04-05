defmodule BorsNG.Database.BatchTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Batch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project

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

    {:ok, installation: installation, project: project}
  end

  test "grab batches that are incomplete", %{project: project} do
    batch0 = Repo.insert!(%Batch{project: project, state: 0})
    batch1 = Repo.insert!(%Batch{project: project, state: 1})
    _batch2 = Repo.insert!(%Batch{project: project, state: 2})
    _batch3 = Repo.insert!(%Batch{project: project, state: 3})
    incomplete = Repo.all(Batch.all_for_project(project.id, :incomplete))
    assert Enum.any?(incomplete, fn batch -> batch.id == batch0.id end)
    assert Enum.any?(incomplete, fn batch -> batch.id == batch1.id end)
    assert Enum.count(incomplete) == 2
  end

  test "grab batches that are complete", %{project: project} do
    _batch0 = Repo.insert!(%Batch{project: project, state: 0})
    _batch1 = Repo.insert!(%Batch{project: project, state: 1})
    batch2 = Repo.insert!(%Batch{project: project, state: 2})
    batch3 = Repo.insert!(%Batch{project: project, state: 3})
    incomplete = Repo.all(Batch.all_for_project(project.id, :complete))
    assert Enum.any?(incomplete, fn batch -> batch.id == batch2.id end)
    assert Enum.any?(incomplete, fn batch -> batch.id == batch3.id end)
    assert Enum.count(incomplete) == 2
  end

  test "get batch by patch", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{project: project})
    Repo.insert!(%LinkPatchBatch{batch: batch, patch: patch})
    [batch_] = Repo.all(Batch.all_for_patch(patch.id))
    assert batch_.id == batch.id
  end

  test "is empty", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    assert Batch.is_empty(batch.id, Repo)
  end

  test "is not empty", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{project: project})
    Repo.insert!(%LinkPatchBatch{batch: batch, patch: patch})
    refute Batch.is_empty(batch.id, Repo)
  end

  test "compute next poll time" do
    p = %Project{batch_delay_sec: 1, batch_poll_period_sec: 2}
    b = %Batch{project: p, last_polled: 3, state: :waiting}
    assert Batch.get_next_poll_unix_sec(b) == 4
    assert Batch.next_poll_is_past(b, 5)
    refute Batch.next_poll_is_past(b, 3)
    b = %Batch{b | state: :running}
    assert Batch.get_next_poll_unix_sec(b) == 5
    assert Batch.next_poll_is_past(b, 6)
    refute Batch.next_poll_is_past(b, 3)
    refute Batch.next_poll_is_past(b, 5)
  end
end
