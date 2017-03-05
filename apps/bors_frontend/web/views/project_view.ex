defmodule BorsNG.ProjectView do
  @moduledoc """
  The list of repository's, and each individual repository page.

  n.b.
  We call it a project internally, though it corresponds
  to a GitHub repository. This is to avoid confusing
  a GitHub repo with an Ecto repo.
  """

  use BorsNG.Web, :view

  def stringify_state(state) do
    case state do
      0 -> "Waiting to run"
      1 -> "Running"
    end
  end
end
