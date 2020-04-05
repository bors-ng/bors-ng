defmodule BorsNG.Worker.Batcher.Divider do
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.GitHub

  def split_batch(patch_links, %Batch{project: project, into_branch: into}) do
    count = Enum.count(patch_links)

    if count > 1 do
      {single_patch_links, patch_links} =
        patch_links
        |> Enum.split_with(fn l ->
          Repo.get!(Patch, l.patch_id).is_single
        end)

      single_patch_links
      |> Enum.each(&clone_batch([&1], project.id, into))

      bisect(patch_links, project.id, into)
      :retrying
    else
      :failed
    end
  end

  def split_batch_with_conflicts(patch_links, %Batch{project: project, into_branch: into}) do
    repo_conn = get_repo_conn(project)

    # if mergeable 0 and unmergeable = 1 -> fail no retry
    #              0                   2+  create single batches for unmergeable patches
    #              1                   0  impossible
    #              1                   1+ create single batches for both
    #              2+                  0  bisect for mergeable patches
    #              2+                  1+ one batch for mergeable patches, create single batches for unmergeable patches
    # Create batches for unmergeable patches first, so they will be picked up first and fail first.
    case isolate_unmergeable_patch_links(patch_links, repo_conn) do
      {[], [_]} ->
        :failed

      {[], multiple_unmergeable} ->
        Enum.each(multiple_unmergeable, fn patch_link ->
          clone_batch([patch_link], project.id, into)
        end)

        :retrying

      {[single_mergeable], multiple_unmergeable} ->
        Enum.each(multiple_unmergeable, fn patch_link ->
          clone_batch([patch_link], project.id, into)
        end)

        clone_batch([single_mergeable], project.id, into)
        :retrying

      {multiple_mergeable, []} ->
        bisect(multiple_mergeable, project.id, into)
        :retrying

      {multiple_mergeable, multiple_unmergeable} ->
        Enum.each(multiple_unmergeable, fn patch_link ->
          clone_batch([patch_link], project.id, into)
        end)

        clone_batch(multiple_mergeable, project.id, into)
        :retrying
    end
  end

  def clone_batch(patch_links, project_id, into_branch) do
    batch = Repo.insert!(Batch.new(project_id, into_branch))

    patch_links
    |> Enum.map(
      &%{
        batch_id: batch.id,
        patch_id: &1.patch_id,
        reviewer: &1.reviewer
      }
    )
    |> Enum.map(&LinkPatchBatch.changeset(%LinkPatchBatch{}, &1))
    |> Enum.each(&Repo.insert!/1)

    batch
  end

  defp bisect(patch_links, project_id, into) do
    count = Enum.count(patch_links)

    {lo, hi} = Enum.split(patch_links, div(count, 2))
    clone_batch(lo, project_id, into)
    clone_batch(hi, project_id, into)
  end

  defp isolate_unmergeable_patch_links(patch_links, repo_conn) do
    patch_link_map =
      patch_links
      |> Enum.group_by(fn patch_link -> is_patch_mergeable(patch_link.patch, repo_conn) end)

    {patch_link_map[true] || [], patch_link_map[false] || []}
  end

  defp is_patch_mergeable(patch, repo_conn) do
    pr = GitHub.get_pr!(repo_conn, patch.pr_xref)
    pr.mergeable == true || pr.mergeable == nil
  end

  @spec get_repo_conn(%Project{}) :: {{:installation, number}, number}
  defp get_repo_conn(project) do
    Project.installation_connection(project.repo_xref, Repo)
  end
end
