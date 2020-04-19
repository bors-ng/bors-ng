defmodule BorsNG.Worker.Batcher.State do
  @moduledoc """
  The batcher state machine.
  It takes a list of status states,
  and emits a batch state.
  """

  @typep status :: BorsNG.Database.Status.t()
  @typep state :: BorsNG.Database.Status.state()

  @spec summary_database_statuses([status]) :: state
  def summary_database_statuses(statuses) do
    statuses
    |> Enum.map(& &1.state)
    |> summary_states()
  end

  @spec summary_states([state]) :: state
  def summary_states(states) do
    states
    |> Enum.reduce(:ok, &summarize/2)
  end

  @spec summarize(state, state) :: state
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
