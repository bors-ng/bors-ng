defmodule Aelita2.WebhookController do
  @moduledoc """
  The webhook controller responds to HTTP requests
  that are initiated from other services (currently, just GitHub).
  """

  use Aelita2.Web, :controller

  alias Aelita2.Attemptor
  alias Aelita2.GitHub
  alias Aelita2.Installation
  alias Aelita2.Patch
  alias Aelita2.Project
  alias Aelita2.Batcher
  alias Aelita2.LinkUserProject
  alias Aelita2.Syncer

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
    sender = payload["sender"]
    |> GitHub.User.from_json!()
    |> Syncer.sync_user()
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
    sender = payload["sender"]
    |> GitHub.User.from_json!()
    |> Syncer.sync_user()
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
    pr = Aelita2.GitHub.Pr.from_json!(conn.body_params["pull_request"])
    patch = Syncer.sync_patch(project.id, pr)
    do_webhook_pr(conn, %{
      action: conn.body_params["action"],
      project: project,
      patch: patch,
      author: patch.author})
  end

  def do_webhook(conn, "github", "issue_comment") do
    if Map.has_key?(conn.body_params["issue"], "pull_request") do
      pr = conn.body_params["repository"]["id"]
      |> Project.installation_connection(Repo)
      |> GitHub.get_pr!(conn.body_params["issue"]["number"])
      project = Repo.get_by!(Project,
        repo_xref: conn.body_params["repository"]["id"])
      commenter = conn.body_params["comment"]["user"]
      |> GitHub.User.from_json!()
      |> Syncer.sync_user()
      comment = conn.body_params["comment"]["body"]
      do_webhook_comment(conn, %{
        project: project,
        pr: pr,
        commenter: commenter,
        comment: comment})
    end
  end

  def do_webhook(conn, "github", "pull_request_review_comment") do
    project = Repo.get_by!(Project,
      repo_xref: conn.body_params["repository"]["id"])
    commenter = conn.body_params["comment"]["user"]
    |> GitHub.User.from_json!()
    |> Syncer.sync_user()
    comment = conn.body_params["comment"]["body"]
    do_webhook_comment(conn, %{
      project: project,
      pr: Aelita2.GitHub.Pr.from_json!(conn.body_params["pull_request"]),
      commenter: commenter,
      comment: comment})
  end

  def do_webhook(conn, "github", "pull_request_review") do
    project = Repo.get_by!(Project,
      repo_xref: conn.body_params["repository"]["id"])
    commenter = conn.body_params["review"]["user"]
    |> GitHub.User.from_json!()
    |> Syncer.sync_user()
    comment = conn.body_params["review"]["body"]
    do_webhook_comment(conn, %{
      project: project,
      pr: Aelita2.GitHub.Pr.from_json!(conn.body_params["pull_request"]),
      commenter: commenter,
      comment: comment})
  end

  def do_webhook(conn, "github", "status") do
    do_webhook_status(
      conn,
      conn.body_params["commit"]["commit"]["message"])
  end

  def do_webhook_status(conn, "Merge " <> _) do
    identifier = conn.body_params["context"]
    commit = conn.body_params["sha"]
    url = conn.body_params["target_url"]
    repo_xref = conn.body_params["repository"]["id"]
    state = GitHub.map_state_to_status(conn.body_params["state"])
    project = Repo.get_by(Project, repo_xref: repo_xref)
    batcher = Batcher.Registry.get(project.id)
    Batcher.status(batcher, {commit, identifier, state, url})
  end

  def do_webhook_status(conn, "Try " <> _) do
    identifier = conn.body_params["context"]
    commit = conn.body_params["sha"]
    url = conn.body_params["target_url"]
    repo_xref = conn.body_params["repository"]["id"]
    state = GitHub.map_state_to_status(conn.body_params["state"])
    project = Repo.get_by(Project, repo_xref: repo_xref)
    attemptor = Attemptor.Registry.get(project.id)
    Attemptor.status(attemptor, {commit, identifier, state, url})
  end

  def do_webhook_status(conn, "[ci skip] -bors-staging-tmp-" <> pr_xref) do
    identifier = conn.body_params["context"]
    err_msg = Batcher.Message.generate_staging_tmp_message(identifier)
    case err_msg do
      nil -> :ok
      err_msg ->
        conn.body_params["repository"]["id"]
        |> Project.installation_connection(Repo)
        |> GitHub.post_comment!(String.to_integer(pr_xref), err_msg)
    end
  end

  def do_webhook_status(_conn, _) do
    :ok
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

  def do_webhook_pr(conn, %{action: "synchronize", project: pro, patch: p}) do
    batcher = Batcher.Registry.get(pro.id)
    Batcher.cancel(batcher, p.id)
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
    title = conn.body_params["pull_request"]["title"]
    body = conn.body_params["pull_request"]["body"]
    Repo.update!(Patch.changeset(patch, %{title: title, body: body}))
  end

  def do_webhook_comment(_conn, params) do
    %{project: project,
      pr: pr,
      commenter: commenter,
      comment: comment} = params
    comment = case comment do
      nil -> ""
      comment -> comment
    end
    p = Syncer.sync_patch(project.id, pr)
    config = Application.get_env(:aelita2, Aelita2)
    activated = :binary.match(comment, config[:activation_phrase])
    deactivated = :binary.match(comment, config[:deactivation_phrase])
    tried = Attemptor.Command.parse(comment)
    cur_branch = pr.base_ref == project.master_branch
    case {activated, deactivated, tried} do
      {:nomatch, :nomatch, :nomatch} -> :ok
      {_, _, _} when cur_branch ->
        link = Repo.get_by(LinkUserProject,
          project_id: project.id,
          user_id: commenter.id)
        case {activated, deactivated, tried, link} do
          {_, _, _, nil} ->
            project.repo_xref
            |> Project.installation_connection(Repo)
            |> GitHub.post_comment!(
              p.pr_xref,
              ":lock: Permission denied")
          {_activated, :nomatch, :nomatch, _} ->
            batcher = Batcher.Registry.get(project.id)
            Batcher.reviewed(batcher, p.id)
          {:nomatch, _deactivated, :nomatch, _} ->
            batcher = Batcher.Registry.get(project.id)
            Batcher.cancel(batcher, p.id)
          {:nomatch, :nomatch, arguments, _} ->
            attemptor = Attemptor.Registry.get(project.id)
            Attemptor.tried(attemptor, p.id, arguments)
          {_, _, _, _} ->
            project.repo_xref
            |> Project.installation_connection(Repo)
            |> GitHub.post_comment!(
              p.pr_xref,
              ":confused: Multiple matching commands")
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
    {:installation, installation_xref}
    |> GitHub.get_installation_repos!()
    |> Enum.filter(& is_nil Repo.get_by(Project, repo_xref: &1.id))
    |> Enum.map(&%Project{repo_xref: &1.id, name: &1.name, installation: i})
    |> Enum.map(&Repo.insert!/1)
    |> Enum.map(&%LinkUserProject{user_id: sender.id, project_id: &1.id})
    |> Enum.map(&Repo.insert!/1)
    |> Enum.each(fn %LinkUserProject{project_id: project_id} ->
      Syncer.start_synchronize_project(project_id)
    end)
  end

  defp project_from_json(json, installation_id) do
    %Project{
      repo_xref: json["id"],
      name: json["full_name"],
      installation_id: installation_id}
  end
end
