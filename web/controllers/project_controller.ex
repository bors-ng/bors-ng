defmodule Aelita2.ProjectController do
  use Aelita2.Web, :controller

  alias Aelita2.LinkUserProject
  alias Aelita2.Project
  alias Aelita2.Batch
  alias Aelita2.Patch
  alias Aelita2.OAuth2.GitHub

  def index(conn, _params) do
    projects = Project.by_owner get_session(conn, :current_user)
    render conn, "index.html", projects: projects
  end

  defp add_project_info(repository) do
    project = Repo.get_by Project, repo_xref: repository.id
    case project do
      nil -> %{repository: repository}
      project -> %{repository: repository, project: project}
    end
  end

  def available(conn, params) do
    import Joken
    key = Application.get_env(:aelita2, Aelita2.Endpoint)[:secret_key_base]
    cur = case params["page"] do
      nil -> nil
      jwt -> (jwt |> token |> with_signer(hs256(key)) |> verify).claims["sub"]
    end
    {my_repos, next} = GitHub.get_my_repos!(get_session(conn, :github_access_token), cur)
    my_repos = Enum.map(my_repos, &add_project_info/1)
    next = case next do
      nil -> nil
      page -> token |> with_sub(page) |> with_signer(hs256(key)) |> sign |> get_compact
    end
    render conn, "available.html", my_repos: my_repos, next: next
  end

  def add(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    token = get_session(conn, :github_access_token)
    _ = GitHub.get_repo! token, project.repo_xref

    Repo.insert! LinkUserProject.changeset(%LinkUserProject{}, %{
      user_id: get_session(conn, :current_user),
      project_id: project.id})

    conn
    |> put_flash(:info, "Project added successfully.")
    |> redirect(to: (project_path conn, :index))
  end

  def show(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    batches = Repo.all(Batch.all_for_project(id))
    |> Enum.map(&%{commit: &1.commit, patches: Repo.all(Patch.all_for_batch(&1.id)), state: &1.state})
    unbatched_patches = Repo.all(Patch.unbatched())
    render conn, "show.html", project: project, batches: batches, unbatched_patches: unbatched_patches
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
