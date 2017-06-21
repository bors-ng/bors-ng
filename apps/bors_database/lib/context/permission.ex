defmodule BorsNG.Database.Context.Permission do
  @moduledoc """
  The connection between a project and its reviewers.

  People with this link can bring up the dashboard page and settings
  for a project, and can r+ a commit. Otherwise, they can't.
  """

  use BorsNG.Database.Context

  def user_has_permission_to_approve_patch(user, patch) do
    %User{id: user_id} = user
    %Patch{id: patch_id, project_id: project_id} = patch
    delegated = UserPatchDelegation
    |> where([d], d.user_id == ^user_id and d.patch_id == ^patch_id)
    |> Repo.one()
    linked = LinkUserProject
    |> where([l], l.user_id == ^user_id and l.project_id == ^project_id)
    |> Repo.one()
    (not is_nil linked) or (not is_nil delegated)
  end
end
