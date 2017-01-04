defmodule Aelita2.ProjectPingChannel do
  use Aelita2.Web, :channel

  alias Aelita2.LinkUserProject

  def join("project_ping:" <> project_id, _message, socket) do
    link = Repo.get_by(LinkUserProject, project_id: project_id, user_id: socket.assigns[:current_user])
    if is_nil(link) do
      {:error, %{reason: "not added"}}
    else
      {:ok, socket}
    end
  end
end
