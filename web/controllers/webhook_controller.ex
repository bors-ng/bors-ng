defmodule Aelita2.WebhookController do
  use Aelita2.Web, :controller

  alias Aelita2.Installation
  alias Aelita2.Patch
  alias Aelita2.Project
  alias Aelita2.User
  alias Aelita2.Batcher
  alias Aelita2.LinkUserProject

  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]

  @doc """
  This action is reached via `/webhook/:provider`
  """
 def webhook(conn, %{"provider" => "github"}) do
    event = hd(get_req_header(conn, "x-github-event"))
    do_webhook conn, "github", event
    conn
    |> send_resp(200, "")
  end

  def do_webhook(_conn, "github", "ping") do
    :ok
  end

  def do_webhook(conn, "github", "integration_installation") do
    payload = conn.body_params
    installation_xref = payload["installation"]["id"]
    sender = sync_user(payload["sender"])
    case payload["action"] do
      "deleted" -> Repo.delete_all(from(
        i in Installation,
        where: i.installation_xref == ^installation_xref
      ))
      "created" -> create_installation_by_xref(installation_xref, sender)
      _ -> nil
    end
    :ok
  end

  def do_webhook(conn, "github", "integration_installation_repositories") do
    payload = conn.body_params
    installation_xref = payload["installation"]["id"]
    installation = Repo.get_by!(Installation, installation_xref: installation_xref)
    :ok = case payload["action"] do
      "removed" -> :ok
      "added" -> :ok
    end
    sender = sync_user(payload["sender"])
    payload["repositories_removed"]
    |> Enum.map(&from(p in Project, where: p.repo_xref == ^&1["id"]))
    |> Enum.each(&Repo.delete_all/1)
    payload["repositories_added"]
    |> Enum.map(&%Project{repo_xref: &1["id"], name: &1["full_name"], installation: installation})
    |> Enum.each(&Repo.insert!/1)
    |> Enum.each(&Repo.insert!(%LinkUserProject{user_id: sender.id, project_id: &1.id}))
    :ok
  end

  def do_webhook(conn, "github", "pull_request") do
    project = Repo.get_by!(Project, repo_xref: conn.body_params["repository"]["id"])
    author = sync_user(conn.body_params["pull_request"]["user"])
    patch = sync_patch(project.id, author.id, conn.body_params["pull_request"])
    do_webhook_pr(conn, conn.body_params["action"], project, patch, author)
  end

  def do_webhook(conn, "github", "issue_comment") do
    if Map.has_key?(conn.body_params["issue"], "pull_request") do
      project = Repo.get_by!(Project, repo_xref: conn.body_params["repository"]["id"])
      patch = Repo.get_by!(Patch, project_id: project.id, pr_xref: conn.body_params["issue"]["number"])
      author = sync_user(conn.body_params["issue"]["user"])
      commenter = sync_user(conn.body_params["comment"]["user"])
      comment = conn.body_params["comment"]["body"]
      do_webhook_comment(conn, "github", project, patch, author, commenter, comment)
    end
  end

  def do_webhook(conn, "github", "pull_request_review_comment") do
    project = Repo.get_by!(Project, repo_xref: conn.body_params["repository"]["id"])
    patch = Repo.get_by!(Patch, project_id: project.id, pr_xref: conn.body_params["issue"]["number"])
    author = sync_user(conn.body_params["issue"]["user"])
    commenter = sync_user(conn.body_params["comment"]["user"])
    comment = conn.body_params["comment"]["body"]
    do_webhook_comment(conn, "github", project, patch, author, commenter, comment)
  end

  def do_webhook(conn, "github", "pull_request_review") do
    project = Repo.get_by!(Project, repo_xref: conn.body_params["repository"]["id"])
    patch = Repo.get_by!(Patch, project_id: project.id, pr_xref: conn.body_params["issue"]["number"])
    author = sync_user(conn.body_params["issue"]["user"])
    commenter = sync_user(conn.body_params["comment"]["user"])
    comment = conn.body_params["comment"]["body"]
    do_webhook_comment(conn, "github", project, patch, author, commenter, comment)
  end

  def do_webhook(conn, "github", "status") do
    identifier = conn.body_params["context"]
    commit = conn.body_params["sha"]
    url = conn.body_params["target_url"]
    state = @github_api.map_state_to_status(conn.body_params["state"])
    Aelita2.Batcher.status(commit, identifier, state, url)
  end

  def do_webhook_pr(_conn, "opened", project, _patch, _author) do
    Project.ping!(project.id)
    :ok
  end

  def do_webhook_pr(_conn, "closed", project, patch, _author) do
    Project.ping!(project.id)
    Repo.update!(Patch.changeset(patch, %{open: false}))
    :ok
  end

  def do_webhook_pr(_conn, "reopened", project, patch, _author) do
    Project.ping!(project.id)
    Repo.update!(Patch.changeset(patch, %{open: false}))
    :ok
  end

  def do_webhook_pr(conn, "synchronize", _project, patch, _author) do
    commit = conn.body_params["pull_request"]["head"]["sha"]
    Repo.update!(Patch.changeset(patch, %{commit: commit}))
  end

  def do_webhook_pr(_conn, "assigned", _project, _patch, _author) do
    :ok
  end

  def do_webhook_pr(_conn, "unassigned", _project, _patch, _author) do
    :ok
  end

  def do_webhook_pr(_conn, "labeled", _project, _patch, _author) do
    :ok
  end

  def do_webhook_pr(_conn, "unlabeled", _project, _patch, _author) do
    :ok
  end

  def do_webhook_pr(conn, "edited", _project, patch, _author) do
    title = conn.title_params["pull_request"]["title"]
    body = conn.body_params["pull_request"]["body"]
    Repo.update!(Patch.changeset(patch, %{title: title, body: body}))
  end

  def do_webhook_comment(_conn, "github", _project, patch, _author, _commenter, comment) do
    activation_phrase = Application.get_env(:aelita2, Aelita2)[:activation_phrase]
    if :binary.match(comment, activation_phrase) != :nomatch do
      Batcher.reviewed(patch.id)
    end
  end

  def create_installation_by_xref(installation_xref, sender) do
    i = Repo.insert!(%Installation{
      installation_xref: installation_xref
    })
    @github_api.Integration.get_installation_token!(installation_xref)
    |> @github_api.Integration.get_my_repos!()
    |> Enum.map(&%Project{repo_xref: &1.id, name: &1.name, installation: i})
    |> Enum.map(&Repo.insert!/1)
    |> Enum.each(&Repo.insert!(%LinkUserProject{user_id: sender.id, project_id: &1.id}))
  end

  def sync_patch(project_id, author_id, patch_json) do
    case Repo.get_by(Patch, project_id: project_id, pr_xref: patch_json["number"]) do
      nil -> Repo.insert!(%Patch{
        project_id: project_id,
        pr_xref: patch_json["number"],
        title: patch_json["title"],
        body: patch_json["body"],
        commit: patch_json["head"]["sha"],
        author_id: author_id,
        open: patch_json["state"] == "open"
      })
      patch -> patch
    end
  end

  def sync_user(user_json) do
    user = case Repo.get_by(User, user_xref: user_json["id"]) do
      nil -> %User{
        id: nil,
        user_xref: user_json["id"],
        login: user_json["login"]}
      user -> user
    end
    if is_nil(user.id) do
      Repo.insert!(user)
    else
      if user.login != user_json["login"] do
        Repo.update! User.changeset(user, %{login: user_json["login"]})
      else
        user
      end
    end
  end
end