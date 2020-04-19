defmodule BorsNG.Worker.Syncer do
  @moduledoc """
  A background task that pulls a full list of opened pull requests from a repo.
  Patches that don't come up get closed,
  and patches that don't exist get created.
  """

  alias BorsNG.Worker.Syncer
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.Database.User
  alias BorsNG.GitHub

  @type tcollaborator :: GitHub.tcollaborator()
  @type trepo_perm :: GitHub.trepo_perm()

  require Logger

  def start_synchronize_project(project) do
    {:ok, _} =
      Task.Supervisor.start_child(
        Syncer.Supervisor,
        fn -> synchronize_project(project) end
      )
  end

  def synchronize_project(%Project{id: id}) do
    synchronize_project(id)
  end

  def synchronize_project(project_id) do
    {:ok, _} = Registry.register(Syncer.Registry, project_id, {})
    conn = Project.installation_project_connection(project_id, Repo)

    open_patches = Repo.all(Patch.all_for_project(project_id, :open))
    open_prs = GitHub.get_open_prs!(conn)
    deltas = synchronize_patches(open_patches, open_prs)
    Enum.each(deltas, &do_synchronize!(project_id, &1))

    synchronize_project_collaborators(conn, project_id)
    Project.ping!(project_id)
  end

  @spec synchronize_project_collaborators_by_role(
          Project.t(),
          [tcollaborator],
          :users | :members,
          trepo_perm | nil
        ) ::
          {:ok, Project.t()} | {:error, any()}
  def synchronize_project_collaborators_by_role(project, collaborators, association, github_perm)
      when association in [:users, :members] and
             github_perm in [:admin, :push, :pull] do
    authorized_users =
      collaborators
      |> Enum.filter(fn %{perms: perms} -> perms[github_perm] end)
      |> Enum.map(fn %{user: user} -> user end)

    Repo.transaction(fn ->
      saved_users =
        authorized_users
        |> Enum.map(&Syncer.sync_user/1)

      project
      |> Repo.preload(association)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(association, saved_users)
      |> Repo.update!()
    end)
  end

  def synchronize_project_collaborators_by_role(project, _, _, nil) do
    {:ok, project}
  end

  def synchronize_project_collaborators(repo_conn, project_id) do
    project = Repo.get!(Project, project_id)

    with {:ok, users} <-
           GitHub.get_collaborators_by_repo(repo_conn),
         {:ok, project} <-
           synchronize_project_collaborators_by_role(
             project,
             users,
             :users,
             project.auto_reviewer_required_perm
           ),
         {:ok, project} <-
           synchronize_project_collaborators_by_role(
             project,
             users,
             :members,
             project.auto_member_required_perm
           ) do
      Logger.debug(["Syncer: refreshed project collaborators", project])
      :ok
    else
      {:error, error} ->
        Logger.warn(["Syncer: Error pulling repo collaborators: ", inspect(error)])
        {:error, error}

      :error ->
        Logger.warn("Syncer: Error pulling repo collaborators (no description)")
    end
  end

  @doc """
  Returns a list of all patches that should be synchronized.

  Note: This will return a list of all opened pull requests,
  as well as a list of patches that should be closed.
  It does not perform any filtering on open PRs, because those
  still need to have their metadata synced.
  """
  @spec synchronize_patches([%Patch{}], [%GitHub.Pr{}]) ::
          [{:open, %GitHub.Pr{}} | {:close, %Patch{}}]
  def synchronize_patches(open_patches, open_prs) do
    open_prs_map =
      open_prs
      |> Enum.map(&{&1.number, &1})
      |> Map.new()

    closings =
      open_patches
      |> Enum.filter(fn %{pr_xref: pr_xref} ->
        not Map.has_key?(open_prs_map, pr_xref)
      end)
      |> Enum.map(&{:close, &1})

    openings = Enum.map(open_prs, &{:open, &1})
    openings ++ closings
  end

  def do_synchronize!(project_id, {:open, pr}) do
    sync_patch(project_id, pr)
  end

  def do_synchronize!(_project_id, {:close, patch}) do
    patch
    |> Patch.changeset(%{open: false})
    |> Repo.update!()
  end

  @spec sync_patch(integer, GitHub.Pr.t()) :: Patch.t()
  def sync_patch(project_id, pr) do
    number = pr.number
    author = sync_user(pr.user)

    data = %{
      project_id: project_id,
      into_branch: pr.base_ref,
      pr_xref: number,
      title: pr.title,
      body: pr.body,
      commit: pr.head_sha,
      author_id: author.id,
      open: pr.state == :open,
      author: author
    }

    case Repo.get_by(Patch, project_id: project_id, pr_xref: number) do
      nil ->
        Repo.insert!(struct(Patch, data))

      patch ->
        patch
        |> Patch.changeset(data)
        |> Repo.update!()
    end
  end

  @spec sync_user(GitHub.User.t()) :: %User{}
  def sync_user(gh_user) do
    case Repo.get_by(User, user_xref: gh_user.id) do
      nil ->
        case Repo.get_by(User, login: gh_user.login) do
          nil ->
            Repo.insert!(%User{
              user_xref: gh_user.id,
              login: gh_user.login
            })

          user ->
            if user.user_xref != gh_user.id do
              Logger.debug(
                "Syncer: sync_user: github user #{inspect(gh_user.login)} changed id from #{
                  inspect(user.user_xref)
                } to #{inspect(gh_user.id)}"
              )

              # Rename the user we had in the database to a login that's not a valid github login
              user
              |> User.changeset(%{login: "#{user.login}/renamed/#{user.id}"})
              |> Repo.update!()

              # And then insert a new one for the actual new user
              Repo.insert!(%User{
                user_xref: gh_user.id,
                login: gh_user.login
              })
            else
              user
            end
        end

      user ->
        if user.login != gh_user.login do
          Logger.debug(
            "Syncer: sync_user: github user id #{inspect(gh_user.user_xref)} changed username from #{
              inspect(user.login)
            } to #{inspect(gh_user.login)}"
          )

          user
          |> User.changeset(%{login: gh_user.login})
          |> Repo.update!()
        else
          user
        end
    end
  end

  @doc """
  Wait for synchronization to finish by hot-spinning.
  Used in test cases.
  """
  def wait_hot_spin(project_id) do
    case Registry.lookup(Syncer.Registry, project_id) do
      [{_, _}] -> wait_hot_spin(project_id)
      _ -> :ok
    end
  end
end
