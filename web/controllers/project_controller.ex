defmodule Aelita2.ProjectController do
  use Aelita2.Web, :controller

  alias Aelita2.LinkUserProject
  alias Aelita2.Project
  alias Aelita2.OAuth2.GitHub

  def index(conn, _params) do
    projects = Repo.all(Project.by_owner get_session(conn, :current_user))
    render conn, "index.html", projects: projects
  end

  defp add_project_info(repository) do
    project = Repo.get_by Project, repo_xref: repository.id
    case project do
      nil -> %{repository: repository}
      project -> %{repository: repository, project: project}
    end
  end

  def available(conn, _params) do
    my_repos = GitHub.get_my_repos!(get_session(conn, :github_access_token))
    |> Enum.map(&add_project_info/1)
    render conn, "available.html", my_repos: my_repos
  end

  def add(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    token = get_session(conn, :github_access_token)
    _ = GitHub.get_repo! token, project.repo_xref

    changeset = LinkUserProject.changeset(%LinkUserProject{}, %{
      user_id: get_session(conn, :user_id),
      project_id: project.id})

    case Repo.insert changeset do
      {:ok, _project} ->
        conn
        |> put_flash(:info, "Project added successfully.")
        |> redirect(to: (project_path conn, :index))
      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to add project.")
        |> redirect(to: (project_path conn, :available))
    end
  end

  def show(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    render conn, "show.html", project: project
  end

  def remove(conn, %{"id" => id}) do
    project = Repo.get! Project, id

    # Here we use delete! (with a bang) because we expect
    # it to always work (and if it does not, it will raise).
    Repo.delete! project

    conn
    |> put_flash(:info, "Project deleted successfully.")
    |> redirect(to: (project_path conn, :index))
  end
end
