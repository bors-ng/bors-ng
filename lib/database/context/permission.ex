defmodule BorsNG.Database.Context.Permission do
  @moduledoc """
  The connection between a project and its reviewers.

  People with this link can bring up the dashboard page and settings
  for a project, and can r+ a commit. Otherwise, they can't.
  """

  use BorsNG.Database.Context

  def list_users_for_project(:member, project_id) do
    Repo.all(
      from(u in User,
        join: l in LinkMemberProject,
        where: l.project_id == ^project_id,
        where: u.id == l.user_id
      )
    )
  end

  def list_users_for_project(:reviewer, project_id) do
    Repo.all(
      from(u in User,
        join: l in LinkUserProject,
        where: l.project_id == ^project_id,
        where: u.id == l.user_id
      )
    )
  end

  def permission?(:member, user, patch) do
    %User{id: user_id} = user
    %Patch{project_id: project_id} = patch

    project_member?(user_id, project_id) or
      permission?(:reviewer, user, patch)
  end

  def permission?(:reviewer, user, patch) do
    %User{id: user_id} = user
    %Patch{id: patch_id, project_id: project_id} = patch

    project_reviewer?(user_id, project_id) or
      patch_delegated_reviewer?(user_id, patch_id)
  end

  def permission?(:none, _, _) do
    true
  end

  def get_permission(nil, _) do
    nil
  end

  def get_permission(user, project) do
    %User{id: user_id} = user
    %Project{id: project_id} = project

    cond do
      project_reviewer?(user_id, project_id) -> :reviewer
      project_member?(user_id, project_id) -> :member
      true -> nil
    end
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
    |> Repo.all()
    |> Enum.empty?()
    |> Kernel.not()
  end

  def delegate(user, patch) do
    Repo.insert!(%UserPatchDelegation{
      user: user,
      patch: patch
    })
  end
end
