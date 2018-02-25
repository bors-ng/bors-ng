defmodule BorsNG.Worker.Attemptor.Registry do
  @moduledoc """
  The "Attemptor" manages the project's try branch.
  This is the registry of each individual attemptor.
  It starts the attemptor if it doesn't exist,
  restarts it if it crashes,
  and logs the crashes because that's needed sometimes.

  Note that the attemptor and registry are always on the same node.
  Sharding between them will be done by directing which registry to go to.
  """

  use GenServer

  alias BorsNG.Worker.Attemptor
  alias BorsNG.Database.Crash
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo

  @name BorsNG.Worker.Attemptor.Registry

  # Public API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def get(project_id) when is_integer(project_id) do
    GenServer.call(@name, {:get, project_id})
  end

  # Server callbacks

  def init(:ok) do
    names = Project
    |> Repo.all()
    |> Enum.map(&{&1.id, do_start(&1.id)})
    |> Map.new()
    refs = names
    |> Enum.map(&{Process.monitor(elem(&1, 1)), elem(&1, 0)})
    |> Map.new()
    {:ok, {names, refs}}
  end

  def do_start(project_id) do
    {:ok, pid} = Attemptor.Supervisor.start(project_id)
    pid
  end

  def handle_call({:get, project_id}, _from, {names, refs}) do
    {pid, names, refs} = case names[project_id] do
      nil ->
        pid = do_start(project_id)
        names = Map.put(names, project_id, pid)
        ref = Process.monitor(pid)
        refs = Map.put(names, ref, project_id)
        {pid, names, refs}
      pid ->
        {pid, names, refs}
    end
    {:reply, pid, {names, refs}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, {names, refs}) do
    {project_id, refs} = Map.pop(refs, ref)
    names = Map.delete(names, project_id)
    if reason != :normal do
      Repo.insert(%Crash{
        project_id: project_id,
        component: "try",
        crash: inspect(reason, pretty: true)})
    end
    {:noreply, {names, refs}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
