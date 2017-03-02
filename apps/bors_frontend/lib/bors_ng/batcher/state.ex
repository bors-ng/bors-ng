defmodule BorsNG.Batcher.State do
  @moduledoc """
  The batcher state machine.
  It takes a list of status states,
  and emits a batch state.
  """

  @typep n :: BorsNG.Status.state_n
  @typep t :: BorsNG.Status.state

  @spec summary_statuses([n]) :: t
  def summary_statuses(statuses) do
    statuses
    |> Enum.map(&(&1.state))
    |> Enum.map(&BorsNG.Status.atomize_state/1)
    |> summary_states()
  end

  @spec summary_states([t]) :: t
  def summary_states(states) do
    states
    |> Enum.reduce(:ok, &summarize/2)
  end

  @spec summarize(t, t) :: t
  def summarize(self, rest) do
    case {self, rest} do
      {:error, _} -> :error
      {_, :error} -> :error
      {:waiting, _} -> :waiting
      {_, :waiting} -> :waiting
      {:running, _} -> :running
      {_, :running} -> :running
      {:ok, x} -> x
    end
  end
end
