defmodule Aelita2.PageController do
  use Aelita2.Web, :controller

  alias Aelita2.Patch

  def index(conn, _params) do
    user = conn.assigns[:user]
    if is_nil(user) do
      render conn, "index.html"
    else
      patches = Repo.all(Patch.all_for_user(user.id, :awaiting_review))
      render conn, "dashboard.html", %{patches: patches}
    end
  end
end
