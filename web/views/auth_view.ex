defmodule Aelita2.AuthView do
  use Aelita2.Web, :view

  def render("socket_token.json", %{token: token}) do
  	token
  end
end
