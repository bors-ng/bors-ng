defmodule BorsNG.Router do
  @moduledoc """
  This module maps from URLs to controllers and plugs.
  It layers on pre-filters, primarily the session, flash,
  CSRF protection, secure headers,
  and user authentication part of the session.
  """

  use BorsNG.Web, :router
  alias BorsNG.Database

  pipeline :browser_page do
    plug(:accepts, ["html"])
  end

  pipeline :browser_ajax do
    plug(:accepts, ["json"])
  end

  pipeline :browser_session do
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:get_current_user)
  end

  pipeline :browser_login do
    plug(:force_current_user)
  end

  pipeline :browser_admin do
    plug(:force_current_user_admin)
  end

  pipeline :webhook do
    plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  end

  scope "/", BorsNG do
    pipe_through(:browser_page)
    pipe_through(:browser_session)
    pipe_through(:browser_login)

    get("/", PageController, :index)
  end

  scope "/batches", BorsNG do
    pipe_through(:browser_page)
    pipe_through(:browser_session)
    pipe_through(:browser_login)

    get("/:id", BatchController, :show)
  end

  scope "/repositories", BorsNG do
    pipe_through(:browser_page)
    pipe_through(:browser_session)
    pipe_through(:browser_login)

    get("/", ProjectController, :index)
    get("/:id", ProjectController, :show)
    get("/:id/settings", ProjectController, :settings)
    put("/:id/settings/branches", ProjectController, :update_branches)
    put("/:id/settings/reviewer", ProjectController, :update_reviewer_settings)
    put("/:id/settings/member", ProjectController, :update_member_settings)
    delete("/:id/batches/incomplete", ProjectController, :cancel_all)
    post("/:id/reviewer", ProjectController, :add_reviewer)
    post("/:id/member", ProjectController, :add_member)
    get("/:id/add-reviewer/:login", ProjectController, :confirm_add_reviewer)
    put("/:id/synchronize", ProjectController, :synchronize)
    get("/:id/log", ProjectController, :log)
    get("/:id/log_page", ProjectController, :log_page)
    delete("/:id/reviewer/:user_id", ProjectController, :remove_reviewer)
    delete("/:id/member/:user_id", ProjectController, :remove_member)
  end

  scope "/admin", BorsNG do
    pipe_through(:browser_page)
    pipe_through(:browser_session)
    pipe_through(:browser_login)
    pipe_through(:browser_admin)

    get("/", AdminController, :index)
    get("/orphans", AdminController, :orphans)
    get("/project", AdminController, :project_by_name)
    get("/dup-patches", AdminController, :dup_patches)
    get("/crashes", AdminController, :crashes)
    post("/synchronize-all-installations", AdminController, :synchronize_all_installations)
  end

  scope "/auth", BorsNG do
    pipe_through(:browser_ajax)
    pipe_through(:browser_session)
    get("/socket-token", AuthController, :socket_token)
  end

  scope "/auth", BorsNG do
    pipe_through(:browser_page)
    pipe_through(:browser_session)

    get("/logout", AuthController, :logout)
    get("/:provider", AuthController, :index)
    get("/:provider/callback", AuthController, :callback)
  end

  scope "/webhook", BorsNG do
    pipe_through(:webhook)
    post("/:provider", WebhookController, :webhook)
  end

  # Fetch the current user from the session and add it to `conn.assigns`. This
  # will allow you to have access to the current user in your views with
  # `@current_user`.

  defp get_current_user(conn, _) do
    user_id = Plug.Conn.get_session(conn, :current_user)

    if is_nil(user_id) do
      conn
    else
      conn
      |> assign(:user, Database.Repo.get(Database.User, user_id))
      |> assign(:avatar_url, Plug.Conn.get_session(conn, :avatar_url))
    end
  end

  defp force_current_user(conn, _) do
    if is_nil(conn.assigns[:user]) do
      conn
      |> Plug.Conn.put_session(:auth_redirect_to, conn.request_path)
      |> Phoenix.Controller.redirect(to: "/auth/github")
      |> halt
    else
      conn
    end
  end

  defp force_current_user_admin(conn, _) do
    case conn do
      %{assigns: %{user: %{is_admin: true}}} ->
        conn

      _ ->
        conn
        |> Plug.Conn.send_resp(403, "Not allowed.")
        |> halt
    end
  end
end
