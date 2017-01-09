defmodule Aelita2.ProjectControllerTest do
  use Aelita2.ConnCase

  alias Aelita2.Installation
  alias Aelita2.Batch
  alias Aelita2.LinkPatchBatch
  alias Aelita2.LinkUserProject
  alias Aelita2.Patch
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

  test "need to log in to see this", %{conn: conn} do
    conn = get conn, project_path(conn, :index)
    assert html_response(conn, 302) =~ "auth"
  end

  def login(conn) do
    conn = get conn, auth_path(conn, :index, "github")
    assert html_response(conn, 302) =~ "MOCK_GITHUB_AUTHORIZE_URL"
    conn = get conn, auth_path(conn, :callback, "github", %{"code" => "MOCK_GITHUB_AUTHORIZE_CODE"})
    html_response(conn, 302)
    conn
  end

  test "do not list unlinked projects", %{conn: conn} do
    conn = login conn
    conn = get conn, project_path(conn, :index)
    refute html_response(conn, 200) =~ "example/project"
  end

  test "list linked projects", %{conn: conn, project: project, user: user} do
    conn = login conn
    Repo.insert! %LinkUserProject{user_id: user.id, project_id: project.id}
    conn = get conn, project_path(conn, :index)
    assert html_response(conn, 200) =~ "example/project"
  end

  test "show an unbatched patch", %{conn: conn, project: project, user: user} do
    conn = login conn
    Repo.insert! %Batch{project_id: project.id}
    Repo.insert! %Patch{project_id: project.id}
    Repo.insert! %LinkUserProject{user_id: user.id, project_id: project.id}
    conn = get conn, project_path(conn, :show, project)
    assert html_response(conn, 200) =~ "Awaiting review"
    refute html_response(conn, 200) =~ "Waiting"
  end

  test "show a batched patch", %{conn: conn, project: project, user: user} do
    conn = login conn
    batch = Repo.insert! %Batch{project_id: project.id, commit: "BC", state: 0}
    patch = Repo.insert! %Patch{project_id: project.id, commit: "PC"}
    Repo.insert! %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id}
    Repo.insert! %LinkUserProject{user_id: user.id, project_id: project.id}
    conn = get conn, project_path(conn, :show, project)
    refute html_response(conn, 200) =~ "Awaiting review"
    assert html_response(conn, 200) =~ "Waiting"
  end
end