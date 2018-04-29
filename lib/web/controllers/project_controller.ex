defmodule BorsNG.ProjectController do
  @moduledoc """
  Shows a list of repositories, a single repository,
  and the repository's settings page.

  n.b.
  We call it a project internally, though it corresponds
  to a GitHub repository. This is to avoid confusing
  a GitHub repo with an Ecto repo.
  """

  use BorsNG.Web, :controller

  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Context.Dashboard
  alias BorsNG.Database.Context.Permission
  alias BorsNG.Database.Repo
  alias BorsNG.Database.LinkMemberProject
  alias BorsNG.Database.LinkUserProject
  alias BorsNG.Database.Project
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Crash
  alias BorsNG.Database.Patch
  alias BorsNG.Database.User
  alias BorsNG.GitHub
  alias BorsNG.Worker.Syncer

  # Auto-grab the project and check the permissions

  def action(conn, _) do
    do_action(conn, action_name(conn), conn.params)
  end

  defp do_action(conn, action, %{"id" => id} = params) do
    allow_private_repos = Confex.fetch_env!(
      :bors, BorsNG)[:allow_private_repos]
    project = Project
    |> from(preload: [:installation])
    |> Repo.get!(id)
    admin? = conn.assigns.user.is_admin
    mode = conn.assigns.user
    |> Permission.get_permission(project)
    |> case do
      _ when admin? -> :rw
      :reviewer -> :rw
      :member -> :ro
      _ when not allow_private_repos -> :ro
      _ -> raise BorsNG.PermissionDeniedError
    end
    apply(__MODULE__, action, [conn, mode, project, params])
  end
  defp do_action(conn, action, params) do
    apply(__MODULE__, action, [conn, params])
  end

  # The actual handlers
  # Two-item ones have a project ID inputed
  # One-item ones don't

  def index(conn, %{"mode" => "reviewer"}) do
    index_(conn, :reviewer)
  end
  def index(conn, %{"mode" => "member"}) do
    index_(conn, :member)
  end
  def index(conn, _params) do
    index_(conn, :all)
  end

  defp index_(conn, filter) do
    projects = Dashboard.my_projects(conn.assigns.user.id, filter)
    render conn, "index.html", projects: projects, filter: filter
  end

  defp batch_info(batch) do
    %{
      commit: batch.commit,
      patches: Repo.all(Patch.all_for_batch(batch.id)),
      state: batch.state}
  end

  def show(conn, mode, project, _params) do
    batches = project.id
    |> Batch.all_for_project(:incomplete)
    |> Repo.all()
    |> Enum.map(&batch_info/1)
    unbatched_patches = project.id
    |> Patch.all_for_project(:awaiting_review)
    |> Repo.all()
    is_synchronizing = match?(
      [{_, _}],
      Registry.lookup(Syncer.Registry, project.id))
    render conn, "show.html",
      project: project,
      batches: batches,
      is_synchronizing: is_synchronizing,
      unbatched_patches: unbatched_patches,
      mode: mode
  end

  def settings(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def settings(conn, :rw, project, _params) do
    reviewers = Permission.list_users_for_project(:reviewer, project.id)
    |> Enum.sort_by(fn %User{login: login} ->
      case conn.assigns[:user].login do
        ^login -> ""
        _ -> login
      end
    end)
    members = Permission.list_users_for_project(:member, project.id)
    |> Enum.sort_by(fn %User{login: login} ->
      case conn.assigns[:user].login do
        ^login -> ""
        _ -> login
      end
    end)
    render conn, "settings.html",
      project: project,
      reviewers: reviewers,
      members: members,
      current_user_id: conn.assigns.user.id,
      update_reviewer_settings:
        Project.changeset_reviewer_settings(project),
      update_member_settings: Project.changeset_member_settings(project),
      update_branches: Project.changeset_branches(project)
  end

  def log(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def log(conn, :rw, project, _params) do
    batches = project.id
    |> Batch.all_for_project()
    |> Repo.all()
    |> Enum.map(fn
      %Batch{id: id} = batch ->
        %{batch | patches: Repo.all(Patch.all_for_batch(id))}
    end)
    crashes = Repo.all(Crash.all_for_project(project.id))
    entries = crashes ++ batches
    |> Enum.sort_by(fn %{updated_at: at} -> NaiveDateTime.to_iso8601(at) end)
    |> Enum.reverse()
    render conn, "log.html",
      project: project,
      current_user_id: conn.assigns.user.id,
      entries: entries
  end

  def cancel_all(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def cancel_all(conn, :rw, project, _params) do
    project.id
    |> Batcher.Registry.get()
    |> Batcher.cancel_all()
    conn
    |> put_flash(:ok, "Canceled all running batches")
    |> redirect(to: project_path(conn, :show, project))
  end

  def update_reviewer_settings(_, :ro, _, _) do
    raise BorsNG.PermissionDeniedError
  end
  def update_reviewer_settings(conn, :rw, project, %{"project" => pdef}) do
    result = project
    |> Project.changeset_reviewer_settings(pdef)
    |> Repo.update()
    case result do
      {:ok, _} ->
        Syncer.start_synchronize_project(project.id)
        conn
        |> put_flash(:ok, "Successfully updated reviewer settings")
        |> redirect(to: project_path(conn, :settings, project))
      {:error, changeset} ->
        reviewers = Permission.list_users_for_project(:reviewer, project.id)
        members = Permission.list_users_for_project(:member, project.id)
        conn
        |> put_flash(:error, "Cannot update branches")
        |> render("settings.html",
          project: project,
          reviewers: reviewers,
          members: members,
          current_user_id: conn.assigns.user.id,
          update_reviewer_settings: changeset,
          update_member_settings: Project.changeset_member_settings(project),
          update_branches: Project.changeset_branches(project))
    end
  end

  def update_member_settings(_, :ro, _, _) do
    raise BorsNG.PermissionDeniedError
  end
  def update_member_settings(conn, :rw, project, %{"project" => pdef}) do
    result = project
    |> Project.changeset_member_settings(pdef)
    |> Repo.update()
    case result do
      {:ok, _} ->
        Syncer.start_synchronize_project(project.id)
        conn
        |> put_flash(:ok, "Successfully updated member settings")
        |> redirect(to: project_path(conn, :settings, project))
      {:error, changeset} ->
        reviewers = Permission.list_users_for_project(:reviewer, project.id)
        members = Permission.list_users_for_project(:member, project.id)
        conn
        |> put_flash(:error, "Cannot update branches")
        |> render("settings.html",
          project: project,
          reviewers: reviewers,
          members: members,
          current_user_id: conn.assigns.user.id,
          update_reviewer_settings:
            Project.changeset_reviewer_settings(project),
          update_member_settings: changeset,
          update_branches: Project.changeset_branches(project))
    end
  end

  def update_branches(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def update_branches(conn, :rw, project, %{"project" => pdef}) do
    result = project
    |> Project.changeset_branches(pdef)
    |> Repo.update()
    case result do
      {:ok, _} ->
        conn
        |> put_flash(:ok, "Successfully updated branches")
        |> redirect(to: project_path(conn, :settings, project))
      {:error, changeset} ->
        reviewers = Permission.list_users_for_project(:reviewer, project.id)
        members = Permission.list_users_for_project(:member, project.id)
        conn
        |> put_flash(:error, "Cannot update branches")
        |> render("settings.html",
          project: project,
          reviewers: reviewers,
          members: members,
          current_user_id: conn.assigns.user.id,
          update_reviewer_settings:
            Project.changeset_reviewer_settings(project),
          update_member_settings: Project.changeset_member_settings(project),
          update_branches: changeset)
    end
  end


  def add_reviewer(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def add_reviewer(conn, :rw, project, %{"reviewer" => %{"login" => ""}}) do
    conn
    |> put_flash(:error, "Please enter a GitHub user's nickname")
    |> redirect(to: project_path(conn, :settings, project))
  end
  def add_reviewer(conn, :rw, project, %{"reviewer" => %{"login" => login}}) do
    user = case Repo.get_by(User, login: login) do
      nil ->
        {:installation, project.installation.installation_xref}
        |> GitHub.get_user_by_login!(login)
        |> case do
          nil -> nil
          gh_user ->
            case Repo.get_by(User, user_xref: gh_user.id) do
              nil ->
                User.changeset(%User{}, %{
                  user_xref: gh_user.id,
                  login: gh_user.login
                })
                |> Repo.insert!()
              user -> user
            end
        end
      user -> user
    end
    {state, msg} = case user do
      nil ->
        {:error, "GitHub user not found; maybe you typo-ed?"}
      user ->
        %LinkUserProject{}
        |> LinkUserProject.changeset(%{
          user_id: user.id,
          project_id: project.id})
        |> Repo.insert()
        |> case do
          {:error, _} ->
            {:error, "This user is already a reviewer"}
          {:ok, _login} ->
            {:ok, "Successfully added #{user.login} as a reviewer"}
        end
    end
    conn
    |> put_flash(state, msg)
    |> redirect(to: project_path(conn, :settings, project))
  end

  def add_member(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def add_member(conn, :rw, project, %{"member" => %{"login" => ""}}) do
    conn
    |> put_flash(:error, "Please enter a GitHub user's nickname")
    |> redirect(to: project_path(conn, :settings, project))
  end
  def add_member(conn, :rw, project, %{"member" => %{"login" => login}}) do
    user = case Repo.get_by(User, login: login) do
      nil ->
        {:installation, project.installation.installation_xref}
        |> GitHub.get_user_by_login!(login)
        |> case do
          nil -> nil
          gh_user ->
            case Repo.get_by(User, user_xref: gh_user.id) do
              nil ->
                User.changeset(%User{}, %{
                  user_xref: gh_user.id,
                  login: gh_user.login
                })
                |> Repo.insert!()
              user -> user
            end
        end
      user -> user
    end
    {state, msg} = case user do
      nil ->
        {:error, "GitHub user not found; maybe you typo-ed?"}
      user ->
        %LinkMemberProject{}
        |> LinkMemberProject.changeset(%{
          user_id: user.id,
          project_id: project.id})
        |> Repo.insert()
        |> case do
          {:error, _} ->
            {:error, "This user is already a member"}
          {:ok, _login} ->
            {:ok, "Successfully added #{user.login} as a member"}
        end
    end
    conn
    |> put_flash(state, msg)
    |> redirect(to: project_path(conn, :settings, project))
  end

  def confirm_add_reviewer(_, :ro, _, _) do
    raise BorsNG.PermissionDeniedError
  end
  def confirm_add_reviewer(
    conn,
    :rw,
    %Project{auto_reviewer_required_perm: nil} = project,
    %{"login" => login}
  ) do
    render conn, "confirm-add-reviewer.html",
      project: project,
      current_user_id: conn.assigns.user.id,
      login: login
  end
  def confirm_add_reviewer(conn, :rw, %Project{name: name}, _) do
    url = Confex.fetch_env!(:bors, :html_github_root)
    url = "#{url}/#{name}/settings/collaboration"
    redirect(conn, external: url)
  end

  def remove_reviewer(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def remove_reviewer(conn, :rw, project, %{"user_id" => user_id}) do
    link = Repo.get_by!(
      LinkUserProject,
      project_id: project.id,
      user_id: user_id)
    Repo.delete!(link)
    conn
    |> put_flash(:ok, "Removed reviewer")
    |> redirect(to: project_path(conn, :settings, project))
  end

  def remove_member(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def remove_member(conn, :rw, project, %{"user_id" => user_id}) do
    link = Repo.get_by!(
      LinkMemberProject,
      project_id: project.id,
      user_id: user_id)
    Repo.delete!(link)
    conn
    |> put_flash(:ok, "Removed member")
    |> redirect(to: project_path(conn, :settings, project))
  end

  def synchronize(_, :ro, _, _), do: raise BorsNG.PermissionDeniedError
  def synchronize(conn, :rw, project, _params) do
    Syncer.start_synchronize_project(project.id)
    conn
    |> put_flash(:ok, "Started synchronizing")
    |> redirect(to: project_path(conn, :show, project))
  end
end
