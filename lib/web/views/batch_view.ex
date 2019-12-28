defmodule BorsNG.BatchView do
  @moduledoc """
  Batch details page
  """

  use BorsNG.Web, :view

  def stringify_state(state) do
    case state do
      :waiting  -> "Waiting to run"
      :running  -> "Running"
      :ok       -> "Succeeded"
      :error    -> "Failed"
      :canceled -> "Canceled"
      _         -> "Invalid"
    end
  end
end
