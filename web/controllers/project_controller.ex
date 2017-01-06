defmodule Aelita2.ProjectController do
  use Aelita2.Web, :controller

  alias Aelita2.Project
  alias Aelita2.Batch
  alias Aelita2.Patch

  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]

  def index(conn, _params) do
    projects = get_session(conn, :current_user)
    |> Project.by_owner()
    |> Repo.all()
    render conn, "index.html", projects: projects
  end

  def show(conn, %{"id" => id}) do
    project = Repo.get! Project, id
    batches = Repo.all(Batch.all_for_project(id, :incomplete))
    |> Enum.map(&%{commit: &1.commit, patches: Repo.all(Patch.all_for_batch(&1.id)), state: &1.state})
    unbatched_patches = Repo.all(Patch.all_for_project(id, :awaiting_review))
    render conn, "show.html", project: project, batches: batches, unbatched_patches: unbatched_patches
  end
end
