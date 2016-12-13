defmodule Aelita2.ProjectController do
  use Aelita2.Web, :controller

  alias Aelita2.Project

  def index(conn, _params) do
    projects = Repo.all(
      from p in Project,
        select: %{name: p.name, id: p.id},
        where: p.user == ^get_session(conn, :current_user))
    render conn, "index.html", projects: projects
  end

  def new(conn, _params) do
    changeset = Project.changeset %Project{}
    render conn, "new.html", changeset: changeset
  end

  def create(conn, %{"project" => project_params}) do
    changeset = Project.changeset %Project{}, project_params

    case Repo.insert changeset do
      {:ok, _project} ->
        conn
        |> put_flash(:info, "Project created successfully.")
        |> redirect(to: (project_path conn, :index))
      {:error, changeset} ->
        render conn, "new.html", changeset: changeset
    end
  end

  def show(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    render conn, "show.html", project: project
  end

  def edit(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    changeset = Project.changeset project
    render conn, "edit.html", project: project, changeset: changeset
  end

  def update(conn, %{"id" => id, "project" => project_params}) do
    project = Repo.get! Project, id
    changeset = Project.changeset project, project_params

    case Repo.update changeset do
      {:ok, project} ->
        conn
        |> put_flash(:info, "Project updated successfully.")
        |> redirect(to: (project_path conn, :show, project))
      {:error, changeset} ->
        render conn, "edit.html", project: project, changeset: changeset
    end
  end

  def delete(conn, %{"id" => id}) do
    project = Repo.get! Project, id

    # Here we use delete! (with a bang) because we expect
    # it to always work (and if it does not, it will raise).
    Repo.delete! project

    conn
    |> put_flash(:info, "Project deleted successfully.")
    |> redirect(to: (project_path conn, :index))
  end
end
