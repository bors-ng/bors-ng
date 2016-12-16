defmodule Aelita2.WebhookController do
  use Aelita2.Web, :controller

  alias Aelita2.Installation
  alias Aelita2.Project

  @doc """
  This action is reached via `/webhook/:provider`
  """
  def webhook(conn, %{"provider" => "github"}) do
    event = hd(get_req_header(conn, "x-github-event"))
    do_webhook conn, "github", event
    conn
    |> send_resp(200, "")
  end

  def do_webhook(conn, "github", "ping") do
    :ok
  end

  def do_webhook(conn, "github", "integration_installation") do
    payload = conn.body_params
    installation_xref = payload["installation"]["id"]
    case payload["action"] do
      "deleted" -> Repo.delete_all(from(
        i in Installation,
        where: i.installation_xref == ^installation_xref
      ))
      "created" -> Repo.insert!(%Installation{
        installation_xref: installation_xref
      })
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
    Enum.each(
      payload["repositories_removed"],
      fn(r) -> Repo.delete_all(from(
        p in Project,
        where: p.repo_xref == ^r["id"])) end)
    Enum.each(
      payload["repositories_added"],
      fn(r) -> Repo.insert! %Project{
        repo_xref: r["id"], name: r["full_name"], installation: installation} end)
    :ok
  end
end