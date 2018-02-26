defmodule BorsNG.WobserverSecurity do
  @moduledoc """
  An implementation of the wobserver security policy.
  This is necessary for one reason: Bors-NG runs on Heroku,
  which establishes every connection from a different load balancer IP.
  The default security policy rejects connections from a different IP than
  """

  alias Plug.Conn

  @spec authenticate(Conn.t) :: Conn.t
  def authenticate(conn) do
    with %{assigns: %{user: %{id: user_id}}} <- conn,
      do: (
        token = Phoenix.Token.sign(
          conn,
          "wobserver:current_user",
          user_id)
        Conn.put_resp_cookie(conn, "conn_wobserver", token))
  end

  @spec authenticated?(Conn.t) :: boolean
  def authenticated?(%Conn{} = conn) do
    conn = Conn.fetch_cookies(conn)
    verify(conn.cookies["conn_wobserver"])
  end

  @spec authenticated?(:cowboy_req.req) :: boolean
  def authenticated?(req) do
    {token, _} = :cowboy_req.cookie("conn_wobserver", req)
    verify(token)
  end

  defp verify(nil) do
    false
  end
  defp verify(token) do
    BorsNG.Endpoint
    |> Phoenix.Token.verify(
      "wobserver:current_user",
      token,
      max_age: 60 * 60)
    |> case do
      {:ok, _} ->
        true
      {:error, _} ->
        false
    end
  end
end
