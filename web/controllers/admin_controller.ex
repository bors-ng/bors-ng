defmodule Aelita2.AdminController do
  use Aelita2.Web, :controller

  alias Aelita2.Project

  # The actual handlers
  # Two-item ones have a project ID inputed
  # One-item ones don't

  def index(conn, _params) do
    orphans = Project.orphans()
    [orphan_count] = from(p in orphans, select: count(p.id))
    |> Repo.all()
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
