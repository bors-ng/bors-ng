defmodule BorsNG.Worker.Batcher.Registry do
  @moduledoc """
  The "Batcher" manages the backlog of batches that each project has.
  This is the registry of each individual batcher.
  It starts the batcher if it doesn't exist,
  restarts it if it crashes,
  and logs the crashes because that's needed sometimes.

  Note that the batcher and registry are always on the same node.
  Sharding between them will be done by directing which registry to go to.
  """

  use GenServer

  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Crash
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo

  @name BorsNG.Worker.Batcher.Registry

  # Public API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def get(project_id) when is_integer(project_id) do
    GenServer.call(@name, {:get, project_id})
  end

  # Server callbacks

  def init(:ok) do
    names =
      Project.active()
      |> Repo.all()
      |> Enum.map(fn %{id: id} -> id end)
      |> Enum.uniq()
      |> Enum.map(&{&1, do_start(&1)})
      |> Map.new()

    refs =
      names
      |> Enum.map(&{Process.monitor(elem(&1, 1)), elem(&1, 0)})
      |> Map.new()

    {:ok, {names, refs}}
  end

  def do_start(project_id) do
    {:ok, pid} = Batcher.Supervisor.start(project_id)
    pid
  end

  def start_and_insert(project_id, {names, refs}) do
    pid = do_start(project_id)
    names = Map.put(names, project_id, pid)
    ref = Process.monitor(pid)
    refs = Map.put(refs, ref, project_id)
    {pid, {names, refs}}
  end

  def handle_call({:get, project_id}, _from, {names, _refs} = state) do
    {pid, state} =
      case names[project_id] do
        nil ->
          start_and_insert(project_id, state)

        pid ->
          {pid, state}
      end

    {:reply, pid, state}
  end

  def handle_info({:DOWN, ref, :process, pid, :normal}, {names, refs}) do
    {project_id, refs} = Map.pop(refs, ref)

    names =
      if names[project_id] == pid do
        Map.delete(names, project_id)
      else
        names
      end

    {:noreply, {names, refs}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, {names, refs}) do
    {project_id, refs} = Map.pop(refs, ref)

    names =
      if names[project_id] == pid do
        Map.delete(names, project_id)
      else
        names
      end

    project_id
    |> Batch.all_for_project(:waiting)
    |> Repo.all()
    |> Enum.each(&Repo.delete!/1)

    project_id
    |> Batch.all_for_project(:running)
    |> Repo.all()
    |> Enum.map(&Batch.changeset(&1, %{state: :canceled}))
    |> Enum.each(&Repo.update!/1)

    Repo.insert(%Crash{
      project_id: project_id,
      component: "batch",
      crash: inspect(reason, pretty: true, width: 60)
    })

    {:noreply, {names, refs}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
