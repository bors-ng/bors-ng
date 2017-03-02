defmodule Aelita2.PageController do
  @moduledoc """
  The controller for the front-page / dashboard.

  This will either show a dashboard, if the user is authenticated,
  or a rundown of what Aelita2 is, if the user is not.
  """

  use Aelita2.Web, :controller

  alias Aelita2.Patch

  def index(conn, _params) do
    user = conn.assigns[:user]
    patches = Repo.all(Patch.all_for_user(user.id, :awaiting_review))
    render conn, "dashboard.html", %{patches: patches}
  end
end
