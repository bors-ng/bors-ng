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

  test "partially cancel a waiting batch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{project_id: proj.id, pr_xref: 1, commit: "N"}
    |> Repo.insert!()
    patch2 = %Patch{project_id: proj.id, pr_xref: 2, commit: "O"}
    |> Repo.insert!()
    batch = %Batch{project_id: proj.id, state: 0} |> Repo.insert!()
    link = %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id}
    |> Repo.insert!()
    link2 = %LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id}
    |> Repo.insert!()
    Batcher.handle_cast({:cancel, patch.id}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => [ "# Canceled" ],
          2 => []
          },
        statuses: %{ "N" => %{ "bors" => :error }},
        files: %{}
      }}
    assert nil == Repo.get(LinkPatchBatch, link.id)
    refute nil == Repo.get(LinkPatchBatch, link2.id)
  end

  test "cancel a running batch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{project_id: proj.id, pr_xref: 1, commit: "N"}
    |> Repo.insert!()
    batch = %Batch{project_id: proj.id, state: 1} |> Repo.insert!()
    %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id} |> Repo.insert!()
    Batcher.handle_cast({:cancel, patch.id}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => [ "# Canceled" ]
          },
        statuses: %{ "N" => %{ "bors" => :error }},
        files: %{}
      }}
    assert Batch.numberize_state(:canceled) == Repo.get(Batch, batch.id).state
  end

  test "ignore cancel on not-running patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{project_id: proj.id, pr_xref: 1} |> Repo.insert!()
    Batcher.handle_cast({:cancel, patch.id}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }}
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
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "N" => %{ "bors" => :running }},
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
        branches: %{
          "master" => "ini",
          "staging" => "iniN",
          "staging.tmp" => "iniN" },
        comments: %{ 1 => [ "# Configuration problem\nbors.toml: not found" ] },
        statuses: %{ "N" => %{ "bors" => :error } },
        files: %{}
      }}
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => %{} },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => %{}, "N" => %{ "bors" => :running } },
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
        branches: %{
          "master" => "ini",
          "staging" => "iniN",
          "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => %{}, "N" => %{ "bors" => :running } },
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
        branches: %{
          "master" => "ini",
          "staging" => "iniN",
          "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => %{}, "N" => %{ "bors" => :running } },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN",
          "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{
          "iniN" => %{ "ci" => :ok },
          "N" => %{ "bors" => :running } },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }})
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN",
          "staging.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{
          "iniN" => %{ "ci" => :ok },
          "N" => %{ "bors" => :running } },
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
        branches: %{
          "master" => "iniN",
          "staging" => "iniN",
          "staging.tmp" => "iniN" },
        comments: %{ 1 => [ "# Build succeeded\n  * ci" ] },
        statuses: %{
          "iniN" => %{ "bors" => :ok, "ci" => :ok },
          "N" => %{ "bors" => :ok } },
        files: %{ "staging" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
  end

  test "infer from .travis.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "staging" => "", "staging.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "staging" => %{ ".travis.yml" => "" } }
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id}, proj.id)
    Batcher.handle_info(:poll, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info(:poll, proj.id)
    [status] = Repo.all(Aelita2.Status)
    assert status.identifier == "continuous-integration/travis-ci/push"
  end
end
