defmodule BorsNG.WebhookParserPlug do
  @moduledoc """
  Parse the GitHub webhook payload (as JSON) and verify the HMAC-SHA1 signature.
  """

  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, options) do
    if conn.path_info == ["webhook", "github"] do
      key = Keyword.get(options, :secret)
      run(conn, options, key)
    else
      conn
    end
  end

  def run(conn, _options, nil) do
    conn
  end

  def run(conn, _options, key) do
    {:ok, body, _} = read_body(conn)

    signature =
      case get_req_header(conn, "x-hub-signature") do
        ["sha1=" <> signature | []] ->
          {:ok, signature} = Base.decode16(signature, case: :lower)
          signature

        x ->
          x
      end

    hmac = :crypto.hmac(:sha, key, body)

    case hmac do
      ^signature ->
        %Plug.Conn{conn | body_params: Poison.decode!(body)}

      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(401, "Invalid signature")
        |> halt
    end
  end
end
