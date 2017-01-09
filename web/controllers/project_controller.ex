defmodule Aelita2.ProjectController do
  use Aelita2.Web, :controller

  alias Aelita2.LinkUserProject
  alias Aelita2.Project
  alias Aelita2.Batch
  alias Aelita2.Patch
  alias Aelita2.User

  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]

  # Auto-grab the project and check the permissions

  def action(conn, _) do
    do_action(conn, action_name(conn), conn.params)
  end

  defp do_action(conn, action, %{"id" => id} = params) do
    project = Repo.get! Project, id
    true = User.has_perm(Repo, conn.assigns.user, project.id)
    apply(__MODULE__, action, [conn, project, params])
  end
  defp do_action(conn, action, params) do
    apply(__MODULE__, action, [conn, params])
  end

  # The actual handlers
  # Two-item ones have a project ID inputed
  # One-item ones don't

  def index(conn, _params) do
    projects = if conn.assigns.user.is_admin do
      Project
    else
      Project.by_owner(conn.assigns.user.id)
    end
    |> Repo.all()
    render conn, "index.html", projects: projects
  end

  def show(conn, project, _params) do
    batches = Repo.all(Batch.all_for_project(project.id, :incomplete))
    |> Enum.map(&%{commit: &1.commit, patches: Repo.all(Patch.all_for_batch(&1.id)), state: &1.state})
    unbatched_patches = Repo.all(Patch.all_for_project(project.id, :awaiting_review))
    render conn, "show.html", project: project, batches: batches, unbatched_patches: unbatched_patches
  end

  def settings(conn, project, _params) do
    reviewers = Repo.all(User.by_project(project.id))
    render conn, "settings.html", project: project, reviewers: reviewers, current_user_id: conn.assigns.user.id
  end

  def add_reviewer(conn, project, %{"reviewer" => %{"login" => login}}) do
    token = get_session(conn, :github_access_token)
    user = case Repo.get_by(User, login: login) do
      nil -> with(
        {:ok, gh_user} <- @github_api.get_user_by_login(token, login),
        user <- %User{user_xref: gh_user.id, login: login},
        do: Repo.insert(user)
      )
      user -> {:ok, user}
    end
    link = with(
      {:ok, user} <- user,
      changeset <- LinkUserProject.changeset(%LinkUserProject{}, %{user_id: user.id, project_id: project.id}),
      do: Repo.insert(changeset)
    )
    {state, msg} = case user do
      {:error, :not_found} -> {:error, "GitHub user not found; maybe you typo-ed?"}
      {:error, _} -> {:error, "Internal error adding user"}
      {:ok, user} ->
        case link do
          {:error, _} -> {:error, "This user is already a reviewer"}
          {:ok, _login} -> {:ok, "Successfully added #{user.login} as a reviewer"}
        end
    end
    conn
    |> put_flash(state, msg)
    |> redirect(to: project_path(conn, :settings, project))
  end

  def remove_reviewer(conn, project, %{"user_id" => user_id}) do
    link = Repo.get_by! LinkUserProject, project_id: project.id, user_id: user_id
    Repo.delete!(link)
    conn
    |> put_flash(:ok, "Removed reviewer")
    |> redirect(to: project_path(conn, :settings, project))
  end
end
