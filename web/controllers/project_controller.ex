defmodule Aelita2.ProjectController do
  use Aelita2.Web, :controller

  alias Aelita2.Project
  alias Aelita2.GitHub

  def index(conn, _params) do
    projects = Repo.all(Project.by_owner get_session(conn, :current_user))
    render conn, "index.html", projects: projects
  end

  def new(conn, _params) do
    my_repos = GitHub.get_my_repos!(get_session(conn, :github_access_token))
    |> Enum.filter(&(&1.permissions.admin))
    render conn, "new.html", my_repos: my_repos
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
