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

  def do_webhook(_conn, "github", "ping") do
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
      "created" -> do_webhook_create_installation installation_xref
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
    payload["repositories_removed"]
    |> Enum.map(&from(p in Project, where: p.repo_xref == ^&1["id"]))
    |> Enum.each(&Repo.delete_all/1)
    payload["repositories_added"]
    |> Enum.map(&%Project{repo_xref: &1["id"], installation: installation})
    |> Enum.each(&Repo.insert!/1)
    :ok
  end

  def do_webhook_create_installation(installation_xref) do
    i = Repo.insert!(%Installation{
      installation_xref: installation_xref
    })
    Aelita2.Integration.GitHub.get_my_repos!(installation_xref)
    |> Enum.map(&%Project{repo_xref: &1.id, name: &1.name, installation: i})
    |> Enum.each(&Repo.insert!/1)
  end
end