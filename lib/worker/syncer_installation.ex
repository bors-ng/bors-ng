defmodule BorsNG.Worker.SyncerInstallation do
  @moduledoc """
  A background task that pulls a full list of repositories that bors is on.
  Projects that don't come up get removed,
  and projects hat don't exist get created.
  """

  alias BorsNG.Worker.Syncer
  alias BorsNG.Worker.SyncerInstallation
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  import Ecto.Query

  require Logger

  def start_synchronize_all_installations do
    {:ok, _} =
      Task.Supervisor.start_child(
        Syncer.Supervisor,
        fn -> synchronize_all_installations() end
      )
  end

  def start_synchronize_installation(installation) do
    {:ok, _} =
      Task.Supervisor.start_child(
        Syncer.Supervisor,
        fn -> synchronize_installation(installation) end
      )
  end

  def synchronize_all_installations do
    GitHub.get_installation_list!()
    |> Enum.each(fn installation_xref ->
      {worker, worker_monitor} =
        spawn_monitor(fn ->
          synchronize_installation(%Installation{
            installation_xref: installation_xref
          })
        end)

      receive do
        {:DOWN, ^worker_monitor, _, _, _} -> :ok
      after
        600_000 -> Process.exit(worker, :kill)
      end
    end)
  end

  def synchronize_installation(
        installation = %Installation{
          installation_xref: x,
          id: id
        }
      )
      when is_integer(x) and is_integer(id) do
    {:ok, _} = Registry.register(SyncerInstallation.Registry, x, {})
    allow_private = Confex.fetch_env!(:bors, BorsNG)[:allow_private_repos]
    repos = GitHub.get_installation_repos!({:installation, x})
    projects = Repo.all(from(p in Project, where: p.installation_id == ^id))

    plan_synchronize(allow_private, repos, projects)
    |> Enum.each(fn {action, payload} ->
      apply(__MODULE__, action, [installation, payload])
    end)
  end

  def synchronize_installation(
        installation = %Installation{
          installation_xref: x
        }
      )
      when is_integer(x) do
    Installation
    |> Repo.get_by(installation_xref: x)
    |> case do
      nil -> Repo.insert!(installation)
      installation -> installation
    end
    |> synchronize_installation()
  end

  def synchronize_installation(id) when is_integer(id) do
    Installation
    |> Repo.get!(id)
    |> synchronize_installation()
  end

  def plan_synchronize(allow_private, repos, projects) do
    repos =
      Enum.flat_map(repos, fn repo = %{id: xref, private: private} ->
        if allow_private || !private, do: [{xref, repo}], else: []
      end)
      |> Map.new()

    projects =
      projects
      |> Enum.map(&{&1.repo_xref, &1})
      |> Map.new()

    adds =
      Enum.flat_map(repos, fn {xref, repo} ->
        if Map.has_key?(projects, xref), do: [], else: [{:add, repo}]
      end)

    removes =
      Enum.flat_map(projects, fn {xref, project} ->
        if Map.has_key?(repos, xref), do: [{:sync, project}], else: [{:remove, project}]
      end)

    adds ++ removes
  end

  def add(%{id: installation_id}, %{id: repo_xref, name: name}) do
    %Project{
      auto_reviewer_required_perm: :push,
      repo_xref: repo_xref,
      name: name,
      installation_id: installation_id
    }
    |> Repo.insert!()
    |> Syncer.synchronize_project()
  end

  def remove(_installation, project) do
    project
    |> Repo.delete!()
  end

  def sync(_installation, project) do
    project
    |> Syncer.synchronize_project()
  end

  @doc """
  Wait for synchronization to finish by hot-spinning.
  Used in test cases.
  """
  def wait_hot_spin_xref(installation_xref) do
    i = Repo.get_by(Installation, installation_xref: installation_xref)
    l = Registry.lookup(SyncerInstallation.Registry, installation_xref)

    case {i, l} do
      # Keep spinning if the installation doesn't exist
      {nil, _} -> wait_hot_spin_xref(installation_xref)
      # Keep spinning if the installation is in the process of syncing
      {_, [{_, _}]} -> wait_hot_spin_xref(installation_xref)
      # Stop spinning otherwise
      _ -> :ok
    end
  end
end
