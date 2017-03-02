defmodule Aelita2.WebhookControllerTest do
  use Aelita2.ConnCase

  alias Aelita2.Patch
  alias Aelita2.Installation
  alias Aelita2.Project
  alias Aelita2.User

  setup do
    installation = Repo.insert!(%Installation{
      installation_xref: 31,
      })
    project = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      })
    user = Repo.insert!(%User{
      user_xref: 23,
      login: "ghost",
      })
    {:ok, installation: installation, project: project, user: user}
  end

  test "edit PR", %{conn: conn, project: project} do
    patch = Repo.insert!(%Patch{
      title: "T",
      body: "B",
      pr_xref: 1,
      project_id: project.id
      })
    body_params = %{
      "repository" => %{ "id" => 13 },
      "action" => "edited",
      "pull_request" => %{
        "number" => 1,
        "title" => "U",
        "body" => "C",
        "state" => "open",
        "base" => %{ "ref" => "N" },
        "head" => %{ "sha" => "S" },
        "user" => %{
          "id" => 23,
          "login" => "ghost",
          "avatar_url" => "U"}}}
    conn
    |> put_req_header("x-github-event", "pull_request")
    |> post(webhook_path(conn, :webhook, "github"), body_params)
    patch2 = Repo.get!(Patch, patch.id)
    assert "U" == patch2.title
    assert "C" == patch2.body
  end
end
