defmodule BorsNG.AuthView do
  @moduledoc """
  The view glue to perform oAuth authentication,
  and to get tokens for sockets and APIs from that.
  """

  use BorsNG.Web, :view

  def render("socket_token.json", %{token: token}) do
    token
  end
end
