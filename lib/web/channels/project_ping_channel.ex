defmodule BorsNG.ProjectPingChannel do
  @moduledoc """
  Phoenix channel for notifying users
  when a repository gets a visible change in its list of PRs.

  This channel gets notified when:

   * the project gets a new patch.
   * a patch goes from "awaiting review" to "waiting"
   * a patch goes from "waiting" to "running"
   * a patch goes from "running" to "awaiting review" (it failed)
   * a patch goes from "running" to "complete" (it passed)
   * a patch changes from "open" to "closed", or from "closed" to "open"
  """

  use BorsNG.Web, :channel

  alias BorsNG.Database.Project
  alias BorsNG.Database.Context.Permission

  def join("project_ping:" <> project_id, _message, socket) do
    (not Confex.fetch_env!(:bors, BorsNG)[:allow_private_repos] ||
       Permission.get_permission(socket.assigns.user, %Project{id: project_id}))
    |> if do
      {:ok, socket}
    else
      {:error, :permission_denied}
    end
  end

  def handle_out(topic, msg, socket) do
    push(socket, topic, msg)
    {:noreply, socket}
  end
end
