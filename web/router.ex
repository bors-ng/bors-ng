defmodule Aelita2.Router do
  use Aelita2.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_session do
    plug :force_current_user
  end

  scope "/", Aelita2 do
    pipe_through :browser

    get "/", PageController, :index
  end

  scope "/manage", Aelita2 do
    pipe_through :browser
    pipe_through :browser_session

    resources "/", ProjectController
  end

  scope "/auth", Aelita2 do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :index
    get "/:provider/callback", AuthController, :callback
  end

  scope "/webhook", Aelita2 do
    post "/:provider", WebhookController, :webhook
  end

  # Fetch the current user from the session and add it to `conn.assigns`. This
  # will allow you to have access to the current user in your views with
  # `@current_user`.
  defp force_current_user(conn, _) do
    user = Plug.Conn.get_session(conn, :current_user)
    if user == nil do
      conn
      |> Phoenix.Controller.redirect(to: "/auth/github")
      |> halt
    else
      assign(conn, :current_user, user)
    end
  end
end
