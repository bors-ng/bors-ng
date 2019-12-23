defmodule BorsNG.BatchControllerTest do
  use BorsNG.ConnCase

  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Status
  alias BorsNG.Database.User

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
    patch = Repo.insert!(%Patch{
      project_id: project.id,
      pr_xref: 43
    })
    batch = Repo.insert!(%Batch{
      project_id: project.id,
      priority: 33
    })
    {:ok, installation: installation, project: project, user: user, batch: batch, patch: patch}
  end

  test "need to log in to see this", %{conn: conn, batch: batch} do
    conn = get conn, "/batches/#{batch.id}"
    assert html_response(conn, 302) =~ "auth"
  end

  def login(conn) do
    conn = get conn, auth_path(conn, :index, "github")
    assert html_response(conn, 302) =~ "MOCK_GITHUB_AUTHORIZE_URL"
    conn = get conn, auth_path(
      conn,
      :callback,
      "github",
      %{"code" => "MOCK_GITHUB_AUTHORIZE_CODE"})
    html_response(conn, 302)
    conn
  end

  test "shows the batch details", %{conn: conn, patch: patch, batch: batch} do
    Repo.insert!(%LinkPatchBatch{
      patch_id: patch.id,
      batch_id: batch.id,
    })
    Repo.insert!(%Status{
      batch_id: batch.id,
      identifier: "some-identifier"
    })
    Repo.insert!(%Status{
      batch_id: batch.id,
      identifier: "with-url-identifier",
      url: "http://example.com"
    })

    conn = login conn
    conn = get conn, "/batches/#{batch.id}"

    assert html_response(conn, 200) =~ "Batch Details"
    assert html_response(conn, 200) =~ "Priority: 33"
    assert html_response(conn, 200) =~ "State: Invalid"
    assert html_response(conn, 200) =~ "#43"
    assert html_response(conn, 200) =~ "<span>some-identifier</span>"
    assert html_response(conn, 200) =~ ~S(<a href="http://example.com">with-url-identifier</a>)
  end

end
