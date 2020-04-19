defmodule BorsNG.Endpoint do
  @moduledoc """
  The set of plugs that are always present,
  including the websocket interceptor and the JSON parser.

  This is what Cowboy calls into.
  """

  use Phoenix.Endpoint, otp_app: :bors

  socket("/socket", BorsNG.UserSocket, websocket: [timeout: 45_000])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :bors,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(BorsNG.WebhookParserPlug,
    secret:
      Confex.get_env(
        :bors,
        BorsNG.WebhookParserPlug
      )[:webhook_secret]
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Poison
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(Plug.Session,
    store: :cookie,
    key: "_bors_key",
    signing_salt: "EQvC5key"
  )

  plug(BorsNG.Router)

  def init(_type, config) do
    Confex.Resolver.resolve(config)
  end
end
