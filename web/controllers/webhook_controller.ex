defmodule Aelita2.WebhookController do
  use Aelita2.Web, :controller

  alias Aelita2.Installation
  alias Aelita2.Project

  @doc """
  This action is reached via `/webhook/:provider`
  """
  def webhook(conn, %{"provider" => "github"}) do
    do_webhook conn, "github", conn.req_headers["X-GitHub-Event"]
  end

  def do_webhook(conn, "github", "integration_installation") do
    payload = Poison.decode!(conn.body)
    installation_id = payload["installation"]["id"]
    case payload["action"] do
      "deleted" -> Repo.delete_all! from(
        i in Installation,
        where i.installation_id = installation_id
      )
      "created" -> Repo.insert! %Installation{
        installation_id: installation_id
      }
    end
  end

  def do_webhook(conn, "github", "integration_installation_repositories") do
    payload = Poison.decode!(conn.body)
    installation_id = payload["installation"]["id"]
    installation = Repo.get(
      from i in Installation, where i.installation_id = installation_id
    )
    :ok = case payload["action"] do
      "removed" -> :ok
      "added" -> :ok
    end
    Enum.each(
      payload["repositories_removed"],
      fn(r) -> Repo.delete_all! from(
        p in Project,
        where p.repo_id = r["id"]))
    Enum.each(
      payload["repositories_added"],
      fn(r) -> Repo.insert! %Project{
        repo_id: r["id"], name: r["full_name"], installation: installation})
  end
end