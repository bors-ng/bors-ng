defmodule BorsNG.BatchController do
  @moduledoc """
  The controller for the batches

  This will either show a batch detail page
  """

  use BorsNG.Web, :controller

  alias BorsNG.Database.Batch
  alias BorsNG.Database.Context.Permission
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Status

  def show(conn, %{"id" => id}) do
    batch = Repo.get(Batch, id)
    project = Repo.get(Project, batch.project_id)

    allow_private_repos = Confex.fetch_env!(:bors, BorsNG)[:allow_private_repos]
    admin? = conn.assigns.user.is_admin

    mode =
      conn.assigns.user
      |> Permission.get_permission(project)
      |> case do
        _ when admin? -> :rw
        :reviewer -> :rw
        :member -> :ro
        _ when not allow_private_repos -> :ro
        _ -> raise BorsNG.PermissionDeniedError
      end

    if mode == :ro do
      raise BorsNG.PermissionDeniedError
    end

    patches = Repo.all(Patch.all_for_batch(batch.id))
    statuses = Repo.all(Status.all_for_batch(batch.id))

    render(conn, "show.html", batch: batch, patches: patches, project: project, statuses: statuses)
  end
end
