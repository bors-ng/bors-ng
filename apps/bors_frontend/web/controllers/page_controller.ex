defmodule BorsNG.PageController do
  @moduledoc """
  The controller for the front-page / dashboard.

  This will either show a dashboard, if the user is authenticated,
  or a rundown of what BorsNG is, if the user is not.
  """

  use BorsNG.Web, :controller

  alias BorsNG.Database.Repo
  alias BorsNG.Database.Patch

  def index(conn, _params) do
    user = conn.assigns[:user]
    patches = Repo.all(Patch.all_for_user(user.id, :awaiting_review))
    render conn, "dashboard.html", %{patches: patches}
  end
end
