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

  alias BorsNG.Database.Repo
  alias BorsNG.Database.User
  alias BorsNG.Endpoint

  def join("project_ping:" <> project_id, _message, socket) do
    with(
      %{assigns: %{user: user}} <- socket,
      true <- User.has_perm(Repo, user, project_id),
      do: {:ok, socket})
  end

  def ping!(project_id) do
    Endpoint.broadcast! "project_ping:#{project_id}", "new_msg", %{}
  end
end
