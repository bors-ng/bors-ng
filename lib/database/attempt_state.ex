defmodule BorsNG.Database.AttemptState do
  @behaviour Ecto.Type
  @moduledoc """
  A type to represent the attmept state.
  """

  @type t :: :waiting | :running | :ok | :error | :canceled
  @typep internal :: 0..4

  # Underlying storage is an integer.
  def type, do: :integer

  @spec cast(t | internal) :: {:ok, t}
  # Accept the integer state values for easier translation of existing code.
  def cast(state) when is_integer(state) do
    case state do
      0 -> {:ok, :waiting}
      1 -> {:ok, :running}
      2 -> {:ok, :ok}
      3 -> {:ok, :error}
      4 -> {:ok, :canceled}
      _ -> :error
    end
  end

  def cast(state) when is_atom(state) do
    case state do
      :waiting -> {:ok, :waiting}
      :running -> {:ok, :running}
      :ok -> {:ok, :ok}
      :error -> {:ok, :error}
      :canceled -> {:ok, :canceled}
      _ -> :error
    end
  end

  def cast(_), do: :error

  @spec load(internal) :: {:ok, t}
  def load(int) when is_integer(int) do
    cast(int)
  end

  @spec dump(t | internal) :: {:ok, internal}
  def dump(term) when is_atom(term) do
    case term do
      :waiting -> {:ok, 0}
      :running -> {:ok, 1}
      :ok -> {:ok, 2}
      :error -> {:ok, 3}
      :canceled -> {:ok, 4}
      _ -> :error
    end
  end

  def dump(term) when is_integer(term) do
    case term do
      0 -> {:ok, 0}
      1 -> {:ok, 1}
      2 -> {:ok, 2}
      3 -> {:ok, 3}
      4 -> {:ok, 4}
      _ -> :error
    end
  end
end
