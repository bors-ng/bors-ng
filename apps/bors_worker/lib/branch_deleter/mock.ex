defmodule BorsNG.Worker.BranchDeleter.Mock do
  @moduledoc """
  BranchDeleter.Mock implements same functions as BranchDeleter.
  But all of them just return :ok
  """

  use GenServer
  alias BorsNG.GitHub.Pr
  alias BorsNG.Database.Patch

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def delete(%Pr{}) do
    :ok
  end

  def delete(%Patch{}) do
    :ok
  end
end
