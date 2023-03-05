defmodule BorsNG.Worker.Batcher.State do
  @moduledoc """
  The batcher state machine.
  It takes a list of status states,
  and emits a batch state.
  """

  @typep status :: BorsNG.Database.Status.t()
  @typep hook :: BorsNG.Database.Hook.t()
  @typep state :: BorsNG.Database.Status.state()

  @spec summary_database_statuses([status]) :: state
  def summary_database_statuses(statuses) do
    statuses
    |> Enum.map(& &1.state)
    |> summary_states()
  end

  @spec summary_hooks_with_status([hook], state) :: state
  def summary_hooks_with_status(hooks, status) do
    hooks
    |> Enum.map(& &1.state)
    |> Enum.map(&case &1 do
      :queued -> :waiting
      :pending -> :running
      x -> x
    end)
    |> summary_states(status)
  end

  @spec summary_states([state]) :: state
  def summary_states(states, default \\ :ok) do
    states
    |> Enum.reduce(default, &summarize/2)
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
