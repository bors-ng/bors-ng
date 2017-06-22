defmodule BorsNG.Database.Context.Permission do
  @moduledoc """
  The connection between a project and its reviewers.

  People with this link can bring up the dashboard page and settings
  for a project, and can r+ a commit. Otherwise, they can't.
  """

  use BorsNG.Database.Context

  def permission_to_approve_patch?(user, patch) do
    %User{id: user_id} = user
    %Patch{id: patch_id, project_id: project_id} = patch
    project_reviewer?(user_id, project_id) or
      patch_delegated_reviewer?(user_id, patch_id)
  end

  def project_reviewer?(user_id, project_id) do
    LinkUserProject
    |> where([l], l.user_id == ^user_id and l.project_id == ^project_id)
    |> Repo.one()
    |> is_nil()
    # elixirc squawks about unary operators if the module is left off.
    |> Kernel.not()
  end

  def patch_delegated_reviewer?(user_id, patch_id) do
    UserPatchDelegation
    |> where([d], d.user_id == ^user_id and d.patch_id == ^patch_id)
    |> Repo.one()
    |> is_nil()
    |> Kernel.not()
  end

  def delegate(user, patch) do
    Repo.insert!(%UserPatchDelegation{
      user: user,
      patch: patch})
  end
end
