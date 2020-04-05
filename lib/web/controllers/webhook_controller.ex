defmodule BorsNG.WebhookController do
  @moduledoc """
  The webhook controller responds to HTTP requests
  that are initiated from other services (currently, just GitHub).

  For example, I can run `iex -S mix phx.server` and do this:

      iex> # Push state to "GitHub"
      iex> alias BorsNG.GitHub
      iex> alias BorsNG.GitHub.ServerMock
      iex> alias BorsNG.Database
      iex> ServerMock.put_state(%{
      ...>   {:installation, 91} => %{ repos: [
      ...>     %GitHub.Repo{
      ...>       id: 14,
      ...>       name: "test/repo",
      ...>       owner: %{
      ...>         id: 6,
      ...>         login: "bors-fanboi",
      ...>         avatar_url: "data:image/svg+xml,<svg></svg>",
      ...>         type: :user
      ...>       }}
      ...>   ] },
      ...>   {{:installation, 91}, 14} => %{
      ...>     branches: %{},
      ...>     comments: %{1 => []},
      ...>     pulls: %{
      ...>       1 => %GitHub.Pr{
      ...>         number: 1,
      ...>         title: "Test",
      ...>         body: "Mess",
      ...>         state: :open,
      ...>         base_ref: "master",
      ...>         head_sha: "00000001",
      ...>         user: %GitHub.User{
      ...>           id: 6,
      ...>           login: "bors-fanboi",
      ...>           avatar_url: "data:image/svg+xml,<svg></svg>"}}},
      ...>     statuses: %{},
      ...>     files: %{}}})
      iex> # The installation now exists; notify bors about it.
      iex> BorsNG.WebhookController.do_webhook(%{
      ...>   body_params: %{
      ...>     "installation" => %{ "id" => 91 },
      ...>     "sender" => %{
      ...>       "id" => 6,
      ...>       "login" => "bors-fanboi",
      ...>       "avatar_url" => "" },
      ...>     "action" => "created" }}, "github", "installation")
      iex> # This starts a background sync process with the installation.
      iex> # Watch it happen in the user interface.
      iex> BorsNG.Worker.SyncerInstallation.wait_hot_spin_xref(91)
      iex> proj = Database.Repo.get_by!(Database.Project, repo_xref: 14)
      iex> proj.name
      "test/repo"
      iex> patch = Database.Repo.get_by!(Database.Patch, pr_xref: 1)
      iex> patch.title
      "Test"
  """

  use BorsNG.Web, :controller

  require Logger

  alias BorsNG.Worker.Attemptor
  alias BorsNG.Worker.Batcher
  alias BorsNG.Worker.BranchDeleter
  alias BorsNG.Command
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub
  alias BorsNG.Worker.Syncer
  alias BorsNG.Worker.SyncerInstallation

  @doc """
  This action is reached via `/webhook/:provider`
  """
  def webhook(conn, %{"provider" => "github"}) do
    event = hd(get_req_header(conn, "x-github-event"))
    do_webhook(conn, "github", event)

    conn
    |> send_resp(200, "")
  end

  def do_webhook(_conn, "github", "ping") do
    :ok
  end

  def do_webhook(conn, "github", "repository"), do: do_webhook_installation_sync(conn)
  def do_webhook(conn, "github", "member"), do: do_webhook_installation_sync(conn)
  def do_webhook(conn, "github", "membership"), do: do_webhook_installation_sync(conn)
  def do_webhook(conn, "github", "team"), do: do_webhook_installation_sync(conn)
  def do_webhook(conn, "github", "organization"), do: do_webhook_installation_sync(conn)

  def do_webhook(conn, "github", "installation") do
    payload = conn.body_params
    installation_xref = payload["installation"]["id"]

    case payload["action"] do
      "deleted" ->
        Repo.delete_all(
          from(
            i in Installation,
            where: i.installation_xref == ^installation_xref
          )
        )

      "created" ->
        SyncerInstallation.start_synchronize_installation(%Installation{
          installation_xref: installation_xref
        })

      _ ->
        nil
    end

    :ok
  end

  def do_webhook(conn, "github", "installation_repositories") do
    SyncerInstallation.start_synchronize_installation(%Installation{
      installation_xref: conn.body_params["installation"]["id"]
    })
  end

  def do_webhook(conn, "github", "pull_request") do
    repo_xref = conn.body_params["repository"]["id"]
    project = Repo.get_by!(Project, repo_xref: repo_xref)
    pr = BorsNG.GitHub.Pr.from_json!(conn.body_params["pull_request"])
    patch = Syncer.sync_patch(project.id, pr)

    do_webhook_pr(conn, %{
      action: conn.body_params["action"],
      project: project,
      patch: patch,
      author: patch.author,
      pr: pr
    })
  end

  def do_webhook(conn, "github", "issue_comment") do
    is_created = conn.body_params["action"] == "created"
    is_pr = Map.has_key?(conn.body_params["issue"], "pull_request")

    if is_created and is_pr do
      project =
        Repo.get_by!(Project,
          repo_xref: conn.body_params["repository"]["id"]
        )

      commenter =
        conn.body_params["comment"]["user"]
        |> GitHub.User.from_json!()
        |> Syncer.sync_user()

      comment = conn.body_params["comment"]["body"]

      %Command{
        project: project,
        commenter: commenter,
        comment: comment,
        pr_xref: conn.body_params["issue"]["number"]
      }
      |> Command.run()
    end
  end

  def do_webhook(conn, "github", "pull_request_review_comment") do
    is_created = conn.body_params["action"] == "created"

    if is_created do
      project =
        Repo.get_by!(Project,
          repo_xref: conn.body_params["repository"]["id"]
        )

      commenter =
        conn.body_params["comment"]["user"]
        |> GitHub.User.from_json!()
        |> Syncer.sync_user()

      comment = conn.body_params["comment"]["body"]
      pr = GitHub.Pr.from_json!(conn.body_params["pull_request"])

      %Command{
        project: project,
        commenter: commenter,
        comment: comment,
        pr_xref: conn.body_params["pull_request"]["number"],
        pr: pr,
        patch: Syncer.sync_patch(project.id, pr)
      }
      |> Command.run()
    end
  end

  def do_webhook(conn, "github", "pull_request_review") do
    is_submitted = conn.body_params["action"] == "submitted"

    if is_submitted do
      project =
        Repo.get_by!(Project,
          repo_xref: conn.body_params["repository"]["id"]
        )

      commenter =
        conn.body_params["review"]["user"]
        |> GitHub.User.from_json!()
        |> Syncer.sync_user()

      comment = conn.body_params["review"]["body"]
      pr = GitHub.Pr.from_json!(conn.body_params["pull_request"])

      %Command{
        project: project,
        commenter: commenter,
        comment: comment,
        pr_xref: conn.body_params["pull_request"]["number"],
        pr: pr,
        patch: Syncer.sync_patch(project.id, pr)
      }
      |> Command.run()
    end
  end

  # The check suite is automatically added by GitHub.
  # But don't start until the user writes "r+"
  def do_webhook(conn, "github", "check_suite") do
    repo_xref = conn.body_params["repository"]["id"]
    branch = conn.body_params["check_suite"]["head_branch"]
    sha = conn.body_params["check_suite"]["head_sha"]
    action = conn.body_params["action"]
    project = Repo.get_by!(Project, repo_xref: repo_xref)
    staging_branch = project.staging_branch
    trying_branch = project.trying_branch

    case {action, branch} do
      {"completed", ^staging_branch} ->
        Batch
        |> Repo.get_by!(commit: sha, project_id: project.id)
        |> Batch.changeset(%{last_polled: 0})
        |> Repo.update!()

        batcher = Batcher.Registry.get(project.id)
        Batcher.poll(batcher)

      {"completed", ^trying_branch} ->
        attemptor = Attemptor.Registry.get(project.id)
        Attemptor.poll(attemptor)

      _ ->
        :ok
    end
  end

  def do_webhook(conn, "github", "check_run") do
    status = conn.body_params["check_run"]["status"]

    case status do
      "completed" ->
        repo_xref = conn.body_params["repository"]["id"]
        commit = conn.body_params["check_run"]["head_sha"]
        url = conn.body_params["check_run"]["html_url"]

        identifier =
          conn.body_params["check_run"]["name"]
          |> GitHub.map_changed_status()

        conclusion = conn.body_params["check_run"]["conclusion"]
        state = GitHub.map_state_to_status(conclusion)

        project = Repo.get_by!(Project, repo_xref: repo_xref)

        batcher = Batcher.Registry.get(project.id)
        Batcher.status(batcher, {commit, identifier, state, url})

        attemptor = Attemptor.Registry.get(project.id)
        Attemptor.status(attemptor, {commit, identifier, state, url})

      _ ->
        :ok
    end
  end

  def do_webhook(conn, "github", "status") do
    repo_xref = conn.body_params["repository"]["id"]
    commit = conn.body_params["commit"]["sha"]

    identifier =
      conn.body_params["context"]
      |> GitHub.map_changed_status()

    url = conn.body_params["target_url"]
    state = GitHub.map_state_to_status(conn.body_params["state"])
    project = Repo.get_by!(Project, repo_xref: repo_xref)
    batcher = Batcher.Registry.get(project.id)
    Batcher.status(batcher, {commit, identifier, state, url})
    attemptor = Attemptor.Registry.get(project.id)
    Attemptor.status(attemptor, {commit, identifier, state, url})
  end

  def do_webhook_installation_sync(conn) do
    payload = conn.body_params
    installation_xref = payload["installation"]["id"]

    SyncerInstallation.start_synchronize_installation(%Installation{
      installation_xref: installation_xref
    })
  end

  def do_webhook_pr(conn, %{
        action: "opened",
        project: project,
        author: author,
        pr: pr,
        patch: patch
      }) do
    Project.ping!(project.id)

    %{
      "pull_request" => %{
        "body" => body,
        "number" => number
      }
    } = conn.body_params

    %Command{
      project: project,
      commenter: author,
      comment: body,
      pr_xref: number,
      pr: pr,
      patch: patch
    }
    |> Command.run()
  end

  def do_webhook_pr(_conn, %{action: "closed", project: project, patch: p}) do
    Project.ping!(project.id)
    Repo.update!(Patch.changeset(p, %{open: false}))
    BranchDeleter.delete(p)
  end

  def do_webhook_pr(conn, %{action: "reopened", project: project, patch: p}) do
    Project.ping!(project.id)
    commit = conn.body_params["pull_request"]["head"]["sha"]
    Repo.update!(Patch.changeset(p, %{open: true, commit: commit}))
  end

  def do_webhook_pr(conn, %{action: "synchronize", project: pro, patch: p}) do
    batcher = Batcher.Registry.get(pro.id)
    Batcher.cancel(batcher, p.id)
    commit = conn.body_params["pull_request"]["head"]["sha"]
    Repo.update!(Patch.changeset(p, %{commit: commit}))
  end

  def do_webhook_pr(conn, %{action: "edited", patch: patch}) do
    %{
      "pull_request" => %{
        "title" => title,
        "body" => body,
        "base" => %{"ref" => base_ref}
      }
    } = conn.body_params

    Repo.update!(
      Patch.changeset(patch, %{
        title: title,
        body: body,
        into_branch: base_ref
      })
    )
  end

  def do_webhook_pr(_conn, %{action: action}) do
    Logger.info(["WebhookController: Got unknown action: ", action])
  end
end
