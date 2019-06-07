defmodule BorsNG.Database.Context.Dashboard do
  @moduledoc """
  Fetch lists by user (for the users' dashboards).
  """

  use BorsNG.Database.Context

  def my_projects(project_id, type \\ :all)

  def my_projects(user_id, :reviewer) do
    from(p in Project,
      join: l in LinkUserProject, on: p.id == l.project_id,
      where: l.user_id == ^user_id,
      order_by: p.repo_xref)
    |> Repo.all()
  end

  def my_projects(user_id, :member) do
    from(p in Project,
      join: l in LinkMemberProject, on: p.id == l.project_id,
      where: l.user_id == ^user_id,
      order_by: p.repo_xref)
    |> Repo.all()
  end

  def my_projects(user_id, :all) do
    my_projects(user_id, :reviewer)
    |> Enum.concat(my_projects(user_id, :member))
    |> Enum.uniq_by(&(&1.repo_xref))
  end

  def my_patches(user_id, type \\ :all)

  def my_patches(user_id, :reviewer) do
    from(p in Patch.all(:awaiting_review),
      preload: :project,
      join: lu in LinkUserProject, on: lu.project_id == p.project_id,
      where: lu.user_id == ^user_id)
    |> Repo.all()
  end

  def my_patches(user_id, :member) do
    from(p in Patch.all(:awaiting_review),
      preload: :project,
      join: lu in LinkMemberProject, on: lu.project_id == p.project_id,
      where: lu.user_id == ^user_id)
    |> Repo.all()
  end

  def my_patches(user_id, :all) do
    my_patches(user_id, :reviewer) ++ my_patches(user_id, :member)
  end
end
