defmodule BorsNG.ServerController do
  @moduledoc """
  The controller for server-related actions such as health checking
  """

  use BorsNG.Web, :controller

  def health(conn, _params) do
    conn |> send_resp(200, "healthy")
  end
end
