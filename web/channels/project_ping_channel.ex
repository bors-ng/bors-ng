defmodule Aelita2.ProjectPingChannel do
  use Aelita2.Web, :channel

  alias Aelita2.User

  def join("project_ping:" <> project_id, _message, socket) do
    if not User.has_perm(Aelita2.Repo, socket.assigns.user, project_id) do
      {:error, %{reason: "not added"}}
    else
      {:ok, socket}
    end
  end
end
