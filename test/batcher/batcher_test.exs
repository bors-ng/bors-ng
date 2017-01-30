defmodule Aelita2.BatcherTest do
  use Aelita2.ModelCase

  alias Aelita2.Batch
  alias Aelita2.Batcher
  alias Aelita2.GitHub
  alias Aelita2.Installation
  alias Aelita2.LinkPatchBatch
  alias Aelita2.Patch
  alias Aelita2.Project

  setup do
    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      master_branch: "master",
      staging_branch: "staging"}
    |> Repo.insert!()
    {:ok, inst: inst, proj: proj}
  end

  test "rejects running patches", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{project_id: proj.id, pr_xref: 1} |> Repo.insert!()
    batch = %Batch{project_id: proj.id, state: 0} |> Repo.insert!()
    %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id} |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => [ "Not awaiting review" ]
          },
        statuses: %{},
        files: %{}
      }}
  end

  test "missing bors.toml", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{project_id: proj.id, pr_xref: 1, commit: "N"} |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{},
        files: %{}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at the same time doesn't change that.
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "iniN", "staging.tmp" => "iniN" },
        comments: %{ 1 => [ "# Configuration problem\nbors.toml: not found" ] },
        statuses: %{},
        files: %{}
      }}
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }})
    patch = %Patch{project_id: proj.id, pr_xref: 1, commit: "N"} |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at the same time doesn't change that.
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "iniN", "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    # Polling again should change nothing.
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    # Force-polling again should still change nothing.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "iniN", "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "iniN", "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [ {"ci", :ok}] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }})
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "iniN", "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [ {"ci", :ok}] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    # Finally, an actual poll should finish it.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "iniN", "staging" => "iniN", "staging.tmp" => "iniN" },
        comments: %{ 1 => [ "# Build succeeded\n  * ci" ] },
        statuses: %{ "iniN" => [ {"ci", :ok}] },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
  end
end
