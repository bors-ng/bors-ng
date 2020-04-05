defmodule BorsNG.BatchView do
  @moduledoc """
  Batch details page
  """

  use BorsNG.Web, :view

  def stringify_state(state) do
    case state do
      :waiting -> "Waiting to run"
      :running -> "Running"
      :ok -> "Succeeded"
      :error -> "Failed"
      :canceled -> "Canceled"
      _ -> "Invalid"
    end
  end

  def htmlify_naive_datetime(datetime) do
    ["<td><time class=time-convert>", NaiveDateTime.to_iso8601(datetime), "+00:00</time></td>"]
    |> Phoenix.HTML.raw()
  end
end
