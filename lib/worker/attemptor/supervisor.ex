defmodule BorsNG.Worker.Attemptor.Supervisor do
  @moduledoc """
  The supervisor of all of the batchers.
  """
  use DynamicSupervisor

  @name BorsNG.Worker.Attemptor.Supervisor

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: @name)
  end

  @spec start(BorsNG.Database.Project.id()) :: {:ok, pid}
  def start(project_id) do
    spec = %{
      id: {BorsNG.Worker.Attemptor, project_id},
      start: {BorsNG.Worker.Attemptor, :start_link, [project_id]}
    }

    DynamicSupervisor.start_child(@name, spec)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
