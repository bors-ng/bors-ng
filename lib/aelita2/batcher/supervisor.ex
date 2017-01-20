defmodule Aelita2.Batcher.Supervisor do
  @moduledoc """
  The supervisor of all of the batchers.
  """
  use Supervisor

  @name Aelita2.Batcher.Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: @name)
  end

  def start(project_id) do
    Supervisor.start_child(@name, [project_id])
  end

  def init(:ok) do
    children = [
      worker(Aelita2.Batcher, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
