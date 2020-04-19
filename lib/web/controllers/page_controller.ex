defmodule BorsNG.PageController do
  @moduledoc """
  The controller for the front-page / dashboard.

  This will either show a dashboard, if the user is authenticated,
  or a rundown of what BorsNG is, if the user is not.
  """

  use BorsNG.Web, :controller

  alias BorsNG.Database.Context.Dashboard

  def index(conn, _params) do
    user = conn.assigns[:user]
    render(conn, "dashboard.html", patches: Dashboard.my_patches(user.id))
  end
end
