defmodule Aelita2.Router do
  use Aelita2.Web, :router

  pipeline :browser_page do
    plug :accepts, ["html"]
  end

  pipeline :browser_ajax do
    plug :accepts, ["json"]
  end

  pipeline :browser_session do
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_login do
    plug :force_current_user
  end

  pipeline :webhook do
    plug Plug.Parsers, parsers: [:json], json_decoder: Poison
  end

  scope "/", Aelita2 do
    pipe_through :browser_page
    pipe_through :browser_session

    get "/", PageController, :index
  end

  scope "/repositories", Aelita2 do
    pipe_through :browser_page
    pipe_through :browser_session
    pipe_through :browser_login

    get "/", ProjectController, :index
    post "/", ProjectController, :add
    get "/available", ProjectController, :available
    get "/available/:page", ProjectController, :available
    get "/:id", ProjectController, :show
    delete "/:id", ProjectController, :remove
  end

  scope "/auth", Aelita2 do
    pipe_through :browser_ajax
    pipe_through :browser_session
    get "/socket-token", AuthController, :socket_token
  end
  scope "/auth", Aelita2 do
    pipe_through :browser_page
    pipe_through :browser_session

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :index
    get "/:provider/callback", AuthController, :callback
  end

  scope "/webhook", Aelita2 do
    pipe_through :webhook
    post "/:provider", WebhookController, :webhook
  end

  # Fetch the current user from the session and add it to `conn.assigns`. This
  # will allow you to have access to the current user in your views with
  # `@current_user`.
  defp force_current_user(conn, _) do
    user = Plug.Conn.get_session(conn, :current_user)
    if user == nil do
      conn
      |> Plug.Conn.put_session(:auth_redirect_to, conn.request_path)
      |> Phoenix.Controller.redirect(to: "/auth/github")
      |> halt
    else
      assign(conn, :current_user, user)
    end
  end
end
