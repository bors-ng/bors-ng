defmodule Aelita2.PatchTest do
  use Aelita2.ModelCase

  alias Aelita2.Batch
  alias Aelita2.Installation
  alias Aelita2.LinkPatchBatch
  alias Aelita2.Project
  alias Aelita2.Patch

  setup do
    installation = Repo.insert!(%Installation{
      installation_xref: 31,
      })
    project = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      })
    {:ok, installation: installation, project: project}
  end

  test "grab patches that are not batched", %{installation: _installation, project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{project: project, pr_xref: 9, title: "T", body: "B", commit: "C"})
    patch2 = Repo.insert!(%Patch{project: project, pr_xref: 10, title: "T", body: "B", commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id})
    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "grab patch from batch", %{installation: _installation, project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{project: project, pr_xref: 9, title: "T", body: "B", commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    _patch2 = Repo.insert!(%Patch{project: project, pr_xref: 10, title: "T", body: "B", commit: "C"})
    [got_patch] = Repo.all(Patch.all_for_batch(batch.id))
    assert got_patch.id == patch.id
  end
end
