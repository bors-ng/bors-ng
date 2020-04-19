defmodule BorsNG.BatchControllerTest do
  use BorsNG.ConnCase

  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.LinkMemberProject
  alias BorsNG.Database.LinkUserProject
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Status
  alias BorsNG.Database.User

  setup do
    installation =
      Repo.insert!(%Installation{
        installation_xref: 31
      })

    project =
      Repo.insert!(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project"
      })

    user =
      Repo.insert!(%User{
        user_xref: 23,
        login: "ghost"
      })

    patch =
      Repo.insert!(%Patch{
        project_id: project.id,
        pr_xref: 43
      })

    batch =
      Repo.insert!(%Batch{
        project_id: project.id,
        priority: 33
      })

    Repo.insert!(%LinkPatchBatch{
      patch_id: patch.id,
      batch_id: batch.id
    })

    Repo.insert!(%Status{
      batch_id: batch.id,
      identifier: "some-identifier",
      state: :running
    })

    Repo.insert!(%Status{
      batch_id: batch.id,
      identifier: "with-url-identifier",
      url: "http://example.com",
      state: :waiting
    })

    {:ok, installation: installation, project: project, user: user, batch: batch, user: user}
  end

  test "need to log in to see this", %{conn: conn, batch: batch} do
    conn = get(conn, "/batches/#{batch.id}")
    assert html_response(conn, 302) =~ "auth"
  end

  def login(conn) do
    conn = get(conn, auth_path(conn, :index, "github"))
    assert html_response(conn, 302) =~ "MOCK_GITHUB_AUTHORIZE_URL"

    conn =
      get(
        conn,
        auth_path(
          conn,
          :callback,
          "github",
          %{"code" => "MOCK_GITHUB_AUTHORIZE_CODE"}
        )
      )

    html_response(conn, 302)
    conn
  end

  test "hides batch details from unlinked user", %{conn: conn, batch: batch} do
    conn = login(conn)

    assert_raise BorsNG.PermissionDeniedError, fn ->
      get(conn, "/batches/#{batch.id}")
    end
  end

  test "shows the batch details as a reviewer", %{
    conn: conn,
    batch: batch,
    user: user,
    project: project
  } do
    Repo.insert!(%LinkUserProject{
      user_id: user.id,
      project_id: project.id
    })

    conn = login(conn)
    conn = get(conn, "/batches/#{batch.id}")

    assert html_response(conn, 200) =~ "Batch Details"
    assert html_response(conn, 200) =~ "Priority: 33"
    assert html_response(conn, 200) =~ "State: Invalid"
    assert html_response(conn, 200) =~ "#43"
    assert html_response(conn, 200) =~ "<span>some-identifier (Running)</span>"

    assert html_response(conn, 200) =~
             ~s(<a href="http://example.com">with-url-identifier (Waiting to run\)</a>)
  end

  test "hides batch details from a member", %{
    conn: conn,
    batch: batch,
    user: user,
    project: project
  } do
    Repo.insert!(%LinkMemberProject{
      user_id: user.id,
      project_id: project.id
    })

    conn = login(conn)

    assert_raise BorsNG.PermissionDeniedError, fn ->
      get(conn, "/batches/#{batch.id}")
    end
  end

  test "shows the batch details for an admin", %{conn: conn, batch: batch, user: user} do
    Repo.update!(User.changeset(user, %{is_admin: true}))

    conn = login(conn)
    conn = get(conn, "/batches/#{batch.id}")

    assert html_response(conn, 200) =~ "Batch Details"
  end
end
