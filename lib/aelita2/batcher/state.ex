defmodule Aelita2.Batcher.State do
  def summary_statuses(statuses) do
    statuses
    |> Enum.map(&(&1.state))
    |> Enum.map(&Aelita2.Status.atomize_state/1)
    |> summary_states()
  end
  def summary_states(states) do
    states
    |> Enum.reduce(:ok, &summarize/2)
  end
  def summarize(self, rest) do
    case {self, rest} do
      {:err, _} -> :err
      {_, :err} -> :err
      {:waiting, _} -> :waiting
      {_, :waiting} -> :waiting
      {:running, _} -> :running
      {_, :running} -> :running
      {:ok, x} -> x
    end
  end
end
