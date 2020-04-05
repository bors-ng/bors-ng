defmodule BorsNG.Database.PatchTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Patch

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

  test "grab patches that are not batched", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    patch2 =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 10,
        title: "T",
        body: "B",
        commit: "C"
      })

    Repo.insert!(%LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id})
    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "grab a patch that is not batched", %{project: project} do
    _batch = Repo.insert!(%Batch{project: project, state: 3})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    [got_patch] = Repo.all(Patch.all(:awaiting_review))
    assert got_patch.id == patch.id
  end

  test "grab an unbatched patch by project", %{
    installation: installation,
    project: project
  } do
    _batch = Repo.insert!(%Batch{project: project, state: 3})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    project2 = Repo.insert!(%Project{installation: installation, repo_xref: 99})

    _patch2 =
      Repo.insert!(%Patch{
        project: project2,
        pr_xref: 10,
        title: "T",
        body: "B",
        commit: "C2"
      })

    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "error batches count as 'awaiting review'", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 3})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "error batches do not force it to be 'awaiting review'", %{
    project: project
  } do
    batch = Repo.insert!(%Batch{project: project, state: 3})
    batch2 = Repo.insert!(%Batch{project: project, state: 0})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch2.id})
    result = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert result == []
  end

  test "batched patch is not 'awaiting review'", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    result = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert result == []
  end

  test "grab patch from batch", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})

    patch =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })

    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})

    _patch2 =
      Repo.insert!(%Patch{
        project: project,
        pr_xref: 10,
        title: "T",
        body: "B",
        commit: "C"
      })

    [got_patch] = Repo.all(Patch.all_for_batch(batch.id))
    assert got_patch.id == patch.id
  end

  test "forbid duplicate patches", %{project: project} do
    Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"
    })

    assert_raise Ecto.InvalidChangesetError, ~r/insert/, fn ->
      %Patch{}
      |> Patch.changeset(%{
        project_id: project.id,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"
      })
      |> Repo.insert!()
    end
  end

  test "allow non-duplicate patches", %{project: project} do
    Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"
    })

    Repo.insert!(%Patch{
      project: project,
      pr_xref: 10,
      title: "T",
      body: "B",
      commit: "C"
    })
  end

  test "allow duplicate patches on different projects", %{project: project} do
    project2 =
      Repo.insert!(%Project{
        installation_id: project.installation_id,
        repo_xref: 14,
        name: "example/project2"
      })

    Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"
    })

    Repo.insert!(%Patch{
      project: project2,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"
    })
  end

  test "ci_skip? checks body" do
    p = %Patch{
      pr_xref: 9,
      title: "T",
      body: "this is \n [ci skip][skip ci][skip netlify]\n it should fail",
      commit: "C"
    }

    assert Patch.ci_skip?(p)
  end

  test "ci_skip? checks title" do
    p = %Patch{
      pr_xref: 9,
      title: "[ci skip][skip ci][skip netlify] title",
      body: "this is body",
      commit: "C"
    }

    assert Patch.ci_skip?(p)
  end

  test "ci_skip? returns false if ci skip is absent" do
    p = %Patch{
      pr_xref: 9,
      title: "title",
      body: "this is body",
      commit: "C"
    }

    refute Patch.ci_skip?(p)
  end
end
