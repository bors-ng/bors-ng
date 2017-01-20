defmodule Aelita2.WebhookController do
  @moduledoc """
  The webhook controller responds to HTTP requests
  that are initiated from other services (currently, just GitHub).
  """

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
      "created" -> Repo.transaction(fn ->
        create_installation_by_xref(installation_xref, sender)
      end)
      _ -> nil
    end
    :ok
  end

  def do_webhook(conn, "github", "integration_installation_repositories") do
    payload = conn.body_params
    installation_xref = payload["installation"]["id"]
    installation = Repo.get_by!(
      Installation,
      installation_xref: installation_xref)
    :ok = case payload["action"] do
      "removed" -> :ok
      "added" -> :ok
    end
    sender = sync_user(payload["sender"])
    payload["repositories_removed"]
    |> Enum.map(&from(p in Project, where: p.repo_xref == ^&1["id"]))
    |> Enum.each(&Repo.delete_all/1)
    payload["repositories_added"]
    |> Enum.map(&project_from_json(&1, installation.id))
    |> Enum.map(&Repo.insert!/1)
    |> Enum.map(&%LinkUserProject{user_id: sender.id, project_id: &1.id})
    |> Enum.each(&Repo.insert!/1)
    :ok
  end

  def do_webhook(conn, "github", "pull_request") do
    repo_xref = conn.body_params["repository"]["id"]
    project = Repo.get_by!(Project, repo_xref: repo_xref)
    author = sync_user(conn.body_params["pull_request"]["user"])
    patch = sync_patch(project.id, author.id, conn.body_params["pull_request"])
    do_webhook_pr(conn, %{
      action: conn.body_params["action"],
      project: project,
      patch: patch,
      author: author})
  end

  def do_webhook(conn, "github", "issue_comment") do
    if Map.has_key?(conn.body_params["issue"], "pull_request") do
      pull_request_json = conn.body_params["repository"]["id"]
      |> Project.installation_connection()
      |> Repo.one!()
      |> @github_api.RepoConnection.connect!()
      |> @github_api.get_pr!(conn.body_params["issue"]["number"])
      project = Repo.get_by!(Project,
        repo_xref: conn.body_params["repository"]["id"])
      author = sync_user(conn.body_params["issue"]["user"])
      commenter = sync_user(conn.body_params["comment"]["user"])
      comment = conn.body_params["comment"]["body"]
      do_webhook_comment(conn, %{
        project: project,
        pull_request_json: pull_request_json,
        author: author,
        commenter: commenter,
        comment: comment})
    end
  end

  def do_webhook(conn, "github", "pull_request_review_comment") do
    project = Repo.get_by!(Project,
      repo_xref: conn.body_params["repository"]["id"])
    author = sync_user(conn.body_params["pull_request"]["user"])
    commenter = sync_user(conn.body_params["comment"]["user"])
    comment = conn.body_params["comment"]["body"]
    do_webhook_comment(conn, %{
      project: project,
      pull_request_json: conn.body_params["pull_request"],
      author: author,
      commenter: commenter,
      comment: comment})
  end

  def do_webhook(conn, "github", "pull_request_review") do
    project = Repo.get_by!(Project,
      repo_xref: conn.body_params["repository"]["id"])
    author = sync_user(conn.body_params["pull_request"]["user"])
    commenter = sync_user(conn.body_params["review"]["user"])
    comment = conn.body_params["review"]["body"]
    do_webhook_comment(conn, %{
      project: project,
      pull_request_json: conn.body_params["pull_request"],
      author: author,
      commenter: commenter,
      comment: comment})
  end

  def do_webhook(conn, "github", "status") do
    identifier = conn.body_params["context"]
    commit = conn.body_params["sha"]
    url = conn.body_params["target_url"]
    repo_xref = conn.body_params["repository"]["id"]
    state = @github_api.map_state_to_status(conn.body_params["state"])
    project = Repo.get_by(Project, repo_xref: repo_xref)
    batcher = Batcher.Registry.get(project.id)
    Batcher.status(batcher, {commit, identifier, state, url})

    commit_msg = conn.body_params["commit"]["commit"]["message"]
    err_msg = Batcher.Message.generate_staging_tmp_message(identifier)
    case commit_msg do
      "-bors-staging-tmp-" <> pr_xref when not is_nil err_msg ->
        conn.body_params["repository"]["id"]
        |> Project.installation_connection()
        |> Repo.one!()
        |> @github_api.RepoConnection.connect!()
        |> @github_api.post_comment!(pr_xref, err_msg)
      _ -> :ok
    end
  end

  def do_webhook_pr(_conn, %{action: "opened", project: project}) do
    Project.ping!(project.id)
    :ok
  end

  def do_webhook_pr(_conn, %{action: "closed", project: project, patch: p}) do
    Project.ping!(project.id)
    Repo.update!(Patch.changeset(p, %{open: false}))
    :ok
  end

  def do_webhook_pr(_conn, %{action: "reopened", project: project, patch: p}) do
    Project.ping!(project.id)
    Repo.update!(Patch.changeset(p, %{open: true}))
    :ok
  end

  def do_webhook_pr(conn, %{action: "synchronize", patch: p}) do
    commit = conn.body_params["pull_request"]["head"]["sha"]
    Repo.update!(Patch.changeset(p, %{commit: commit}))
  end

  def do_webhook_pr(_conn, %{action: "assigned"}) do
    :ok
  end

  def do_webhook_pr(_conn, %{action: "unassigned"}) do
    :ok
  end

  def do_webhook_pr(_conn, %{action: "labeled"}) do
    :ok
  end

  def do_webhook_pr(_conn, %{action: "unlabeled"}) do
    :ok
  end

  def do_webhook_pr(conn, %{action: "edited", patch: patch}) do
    title = conn.title_params["pull_request"]["title"]
    body = conn.body_params["pull_request"]["body"]
    Repo.update!(Patch.changeset(patch, %{title: title, body: body}))
  end

  def do_webhook_comment(_conn, params) do
    %{project: project,
      pull_request_json: pull_request_json,
      author: author,
      commenter: commenter,
      comment: comment} = params
    comment = case comment do
      nil -> ""
      comment -> comment
    end
    p = sync_patch(project.id, author.id, pull_request_json)
    config = Application.get_env(:aelita2, Aelita2)
    activated = :binary.match(comment, config[:activation_phrase])
    deactivated = :binary.match(comment, config[:deactivation_phrase])
    cur_branch = pull_request_json["base"]["ref"] == project.master_branch
    case {activated, deactivated} do
      {:nomatch, :nomatch} -> :ok
      {_, _} when cur_branch ->
        link = Repo.get_by(LinkUserProject,
          project_id: project.id,
          user_id: commenter.id)
        batcher = Batcher.Registry.get(project.id)
        case {activated, deactivated, link} do
          {_, _, nil} ->
            project.repo_xref
            |> Project.installation_connection()
            |> Repo.one!()
            |> @github_api.RepoConnection.connect!()
            |> @github_api.post_comment!(
              p.pr_xref,
              ":lock: Permission denied")
          {_activated, :nomatch, _} ->
            Batcher.reviewed(batcher, p.id)
          {:nomatch, _deactivated, _} ->
            Batcher.cancel(batcher, p.id)
        end
    end
  end

  def create_installation_by_xref(installation_xref, sender) do
    i = case Repo.get_by(Installation, installation_xref: installation_xref) do
      nil -> Repo.insert!(%Installation{
        installation_xref: installation_xref
      })
      i -> i
    end
    installation_xref
    |> @github_api.Integration.get_installation_token!()
    |> @github_api.Integration.get_my_repos!()
    |> Enum.filter(& is_nil Repo.get_by(Project, repo_xref: &1.id))
    |> Enum.map(&%Project{repo_xref: &1.id, name: &1.name, installation: i})
    |> Enum.map(&Repo.insert!/1)
    |> Enum.map(&%LinkUserProject{user_id: sender.id, project_id: &1.id})
    |> Enum.each(&Repo.insert!/1)
  end

  def sync_patch(project_id, author_id, patch_json) do
    number = patch_json["number"]
    case Repo.get_by(Patch, project_id: project_id, pr_xref: number) do
      nil -> Repo.insert!(%Patch{
        project_id: project_id,
        pr_xref: number,
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

  defp project_from_json(json, installation_id) do
    %Project{
      repo_xref: json["id"],
      name: json["full_name"],
      installation_id: installation_id}
  end
end
