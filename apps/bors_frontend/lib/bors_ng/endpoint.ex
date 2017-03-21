defmodule BorsNG.Endpoint do
  @moduledoc """
  The set of plugs that are always present,
  including the websocket interceptor and the JSON parser.

  This is what Cowboy calls into.
  """

  @wobserver_url Application.get_env(:wobserver, :remote_url_prefix)

  use Phoenix.Endpoint, otp_app: :bors_frontend

  socket "/socket", BorsNG.UserSocket
  socket @wobserver_url, Wobserver.Web.PhoenixSocket

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/", from: :bors_frontend, gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Logger

  plug BorsNG.WebhookParserPlug,
    secret: Application.get_env(
      :bors_frontend,
      BorsNG.WebhookParserPlug)[:webhook_secret]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Poison

  plug Plug.MethodOverride
  plug Plug.Head

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session,
    store: :cookie,
    key: "_aelita2_key",
    signing_salt: "EQvC5key"

  plug BorsNG.Router
end
