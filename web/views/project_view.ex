defmodule Aelita2.ProjectView do
  use Aelita2.Web, :view
  def stringify_state(state) do
    case state do
      0 -> "Waiting"
      1 -> "Running"
    end
  end
end
