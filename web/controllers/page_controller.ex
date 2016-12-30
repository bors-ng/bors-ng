defmodule Aelita2.PageController do
  use Aelita2.Web, :controller

  alias Aelita2.Patch

  def index(conn, _params) do
    user_id = get_session(conn, :current_user)
    if is_nil(user_id) do
      render conn, "index.html"
    else
      patches = Repo.all(Patch.all_for_user(user_id, :awaiting_review))
      render conn, "dashboard.html", %{patches: patches}
    end
  end
end
