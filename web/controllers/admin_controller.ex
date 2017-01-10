defmodule Aelita2.AdminController do
  @moduledoc """
  Functionality that is specific to administrators.

  Administrators are users with the `is_admin` flag set.
  Ensuring non-administrators can't get here is done in `Aelita2.Router`.

  Administrators have the ability to step outside the permissions
  and edit any repo, or delete it if they wish.
  """

  use Aelita2.Web, :controller

  alias Aelita2.Project

  # The actual handlers
  # Two-item ones have a project ID inputed
  # One-item ones don't

  def index(conn, _params) do
    orphans = Project.orphans()
    orphan_count = from(p in orphans, select: count(p.id))
    [orphan_count] = Repo.all(orphan_count)
    render conn, "index.html", orphan_count: orphan_count
  end

  def orphans(conn, _params) do
    orphans = Repo.all Project.orphans()
    render conn, "orphans.html", orphans: orphans
  end

  def project_by_name(conn, %{"project" => %{"name" => name}}) do
    project = Repo.get_by! Project, name: name
    redirect conn, to: project_path(conn, :show, project.id)
  end
end
