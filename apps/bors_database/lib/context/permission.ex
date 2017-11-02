defmodule BorsNG.Database.Context.Permission do
  @moduledoc """
  The connection between a project and its reviewers.

  People with this link can bring up the dashboard page and settings
  for a project, and can r+ a commit. Otherwise, they can't.
  """

  use BorsNG.Database.Context

  def has_permission?(:member, user, patch) do
    %User{id: user_id} = user
    %Patch{project_id: project_id} = patch
    project_member?(user_id, project_id) or
      has_permission?(:reviewer, user, patch)
  end
  def has_permission?(:reviewer, user, patch) do
    %User{id: user_id} = user
    %Patch{id: patch_id, project_id: project_id} = patch
    project_reviewer?(user_id, project_id) or
      patch_delegated_reviewer?(user_id, patch_id)
  end
  def has_permission?(:none, _, _) do
    true
  end

  defp project_reviewer?(user_id, project_id) do
    LinkUserProject
    |> where([l], l.user_id == ^user_id and l.project_id == ^project_id)
    |> Repo.one()
    |> is_nil()
    # elixirc squawks about unary operators if the module is left off.
    |> Kernel.not()
  end

  defp project_member?(user_id, project_id) do
    LinkMemberProject
    |> where([l], l.user_id == ^user_id and l.project_id == ^project_id)
    |> Repo.one()
    |> is_nil()
    # elixirc squawks about unary operators if the module is left off.
    |> Kernel.not()
  end

  defp patch_delegated_reviewer?(user_id, patch_id) do
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
