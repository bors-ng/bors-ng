defmodule Aelita2.PatchTest do
  use Aelita2.ModelCase

  alias Aelita2.Batch
  alias Aelita2.Installation
  alias Aelita2.LinkPatchBatch
  alias Aelita2.LinkUserProject
  alias Aelita2.Project
  alias Aelita2.Patch
  alias Aelita2.User

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

  test "grab patches that are not batched", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    patch2 = Repo.insert!(%Patch{
      project: project,
      pr_xref: 10,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id})
    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "grab a patch that is not batched", %{project: project} do
    _batch = Repo.insert!(%Batch{project: project, state: 3})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    [got_patch] = Repo.all(Patch.all(:awaiting_review))
    assert got_patch.id == patch.id
  end

  test "grab an unbatched patch by project", %{
    installation: installation,
    project: project} do
    _batch = Repo.insert!(%Batch{project: project, state: 3})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    project2 = Repo.insert!(%Project{installation: installation, repo_xref: 99})
    _patch2 = Repo.insert!(%Patch{
      project: project2,
      pr_xref: 10,
      title: "T",
      body: "B",
      commit: "C2"})
    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "error batches count as 'awaiting review'", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 3})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    [got_patch] = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "error batches do not force it to be 'awaiting review'", %{
    project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 3})
    batch2 = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch2.id})
    result = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert result == []
  end

  test "batched patch is not 'awaiting review'", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    result = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    assert result == []
  end

  test "grab patch from batch", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch.id, batch_id: batch.id})
    _patch2 = Repo.insert!(%Patch{
      project: project,
      pr_xref: 10,
      title: "T",
      body: "B",
      commit: "C"})
    [got_patch] = Repo.all(Patch.all_for_batch(batch.id))
    assert got_patch.id == patch.id
  end

  test "grab patches that a particular user has", %{project: project} do
    batch = Repo.insert!(%Batch{project: project, state: 0})
    patch = Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    patch2 = Repo.insert!(%Patch{
      project: project,
      pr_xref: 10,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id})
    user = Repo.insert!(%User{})
    Repo.insert!(%LinkUserProject{user_id: user.id, project_id: project.id})
    [got_patch] = Repo.all(Patch.all_for_user(user.id, :awaiting_review))
    assert got_patch.id == patch.id
  end

  test "forbid duplicate patches", %{project: project} do
    Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    assert_raise Ecto.InvalidChangesetError, ~r/insert/, fn ->
      %Patch{}
      |> Patch.changeset(%{
        project_id: project.id,
        pr_xref: 9,
        title: "T",
        body: "B",
        commit: "C"})
      |> Repo.insert!()
    end
  end

  test "allow non-duplicate patches", %{project: project} do
    Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%Patch{
      project: project,
      pr_xref: 10,
      title: "T",
      body: "B",
      commit: "C"})
  end

  test "allow duplicate patches on different projects", %{project: project} do
    project2 = Repo.insert!(%Project{
      installation_id: project.installation_id,
      repo_xref: 14,
      name: "example/project2"})
    Repo.insert!(%Patch{
      project: project,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
    Repo.insert!(%Patch{
      project: project2,
      pr_xref: 9,
      title: "T",
      body: "B",
      commit: "C"})
  end
end
