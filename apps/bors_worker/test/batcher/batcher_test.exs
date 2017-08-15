defmodule BorsNG.Worker.BatcherTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Status
  alias BorsNG.GitHub

  import Ecto.Query

  setup do
    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      staging_branch: "staging"}
    |> Repo.insert!()
    {:ok, inst: inst, proj: proj}
  end

  test "cancel all", %{proj: proj} do
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    batch = %Batch{
      project_id: proj.id,
      state: 0,
      into_branch: "master"}
    |> Repo.insert!()
    link = %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id}
    |> Repo.insert!()
    link2 = %LinkPatchBatch{patch_id: patch2.id, batch_id: batch.id}
    |> Repo.insert!()
    Batcher.handle_cast({:cancel_all}, proj.id)
    assert nil == Repo.get(LinkPatchBatch, link.id)
    assert nil == Repo.get(LinkPatchBatch, link2.id)
  end

  test "partially cancel a waiting batch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    batch = %Batch{
      project_id: proj.id,
      state: 0,
      into_branch: "master"}
    |> Repo.insert!()
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
          1 => ["# Canceled"],
          2 => []
          },
        statuses: %{"N" => %{"bors" => :error}},
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
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    batch = %Batch{
      project_id: proj.id,
      state: 1,
      into_branch: "master"}
    |> Repo.insert!()
    %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id} |> Repo.insert!()
    Batcher.handle_cast({:cancel, patch.id}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => ["# Canceled"]
          },
        statuses: %{"N" => %{"bors" => :error}},
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
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      into_branch: "master"}
    |> Repo.insert!()
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
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      into_branch: "master"}
    |> Repo.insert!()
    batch = %Batch{
      project_id: proj.id,
      state: 0,
      into_branch: "master"}
    |> Repo.insert!()
    %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id} |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => ["Not awaiting review"]
          },
        statuses: %{},
        files: %{}
      }}
  end

  test "rejects a patch with a blocked label", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        labels: %{1 => ["no"]},
        statuses: %{"Z" => %{}},
        files: %{"Z" => %{"bors.toml" =>
          ~s/status = [ "ci" ]\nblock_labels = [ "no" ]/}},
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "Z",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => [":-1: Rejected by label"]},
        labels: %{1 => ["no"]},
        statuses: %{"Z" => %{"bors" => :error}},
        files: %{"Z" => %{"bors.toml" =>
          ~s/status = [ "ci" ]\nblock_labels = [ "no" ]/}},
      }}
  end

  test "rejects a patch with a bad PR status", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{"Z" => %{"cn" => :error}},
        files: %{"Z" => %{"bors.toml" =>
          ~s/status = [ "ci" ]\npr_status = [ "cn" ]/}},
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "Z",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => [":-1: Rejected by PR status"]},
        statuses: %{"Z" => %{"bors" => :error, "cn" => :error}},
        files: %{"Z" => %{"bors.toml" =>
          ~s/status = [ "ci" ]\npr_status = [ "cn" ]/}},
      }}
  end

  test "missing bors.toml", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at the same time doesn't change that.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini",
          "staging" => ""},
        comments: %{1 => ["# Configuration problem\nbors.toml: not found"]},
        statuses: %{"N" => %{"bors" => :error}},
        files: %{}
      }}
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}, "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at the same time doesn't change that.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}, "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Polling again should change nothing.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    # Force-polling again should still change nothing.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}, "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => []},
        statuses: %{
          "iniN" => %{"ci" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => []},
        statuses: %{
          "iniN" => %{"ci" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Finally, an actual poll should finish it.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniN",
          "staging" => "iniN"},
        comments: %{1 => ["# Build succeeded\n  * ci"]},
        statuses: %{
          "iniN" => %{"bors" => :ok, "ci" => :ok},
          "N" => %{"bors" => :ok}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
  end

  test "full runthrough and continue", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Submit the second one.
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Push the second one's timer, so it'll start now.
    {batch, batch2} = case Repo.all(Batch) do
      [batch1, batch2] ->
        if batch1.id == batch.id do
          {batch1, batch2}
        else
          {batch2, batch1}
        end
    end
    batch2
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    # Finally, finish it.
    Batcher.do_handle_cast({:status, {"iniN", "ci", :ok, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniN",
          "staging" => "iniNO"},
        comments: %{1 => ["# Build succeeded\n  * ci"], 2 => []},
        statuses: %{
          "iniN" => %{"bors" => :ok},
          "N" => %{"bors" => :ok},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
  end

  test "full runthrough with priority putting one on hold", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Submit the second one, with a higher priority.
    Batcher.handle_call({:set_priority, patch2.id, 10}, nil, proj.id)
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    # Push the second one's timer, so it'll start now.
    {batch, batch2} = case Repo.all(Batch) do
      [batch1, batch2] ->
        if batch1.id == batch.id do
          {batch1, batch2}
        else
          {batch2, batch1}
        end
    end
    batch2
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    # The second one should now be the one running,
    # with the first one pushed back to the backlog.
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Finally, finish the higher-priority, second batch.
    Batcher.do_handle_cast({:status, {"iniO", "ci", :ok, nil}}, proj.id)
    batch2 = Repo.get! Batch, batch2.id
    assert batch2.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniO",
          "staging" => "iniO"},
        comments: %{2 => ["# Build succeeded\n  * ci"], 1 => []},
        statuses: %{
          "iniO" => %{"bors" => :ok},
          "O" => %{"bors" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Poll again, so that the first, lower-priority batch is started again.
    batch2
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniO",
          "staging" => "iniON"},
        comments: %{2 => ["# Build succeeded\n  * ci"], 1 => []},
        statuses: %{
          "iniN" => %{"bors" => :running}, # TODO #263 make this :error
          "iniO" => %{"bors" => :ok},
          "O" => %{"bors" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Finish the first one, since the higher-priority item is past it now
    Batcher.do_handle_cast({:status, {"iniON", "ci", :ok, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniON",
          "staging" => "iniON"},
        comments: %{
          2 => ["# Build succeeded\n  * ci"],
          1 => ["# Build succeeded\n  * ci"]},
        statuses: %{
          "iniN" => %{"bors" => :running}, # TODO #263 make this :error
          "iniON" => %{"bors" => :ok},
          "iniO" => %{"bors" => :ok},
          "O" => %{"bors" => :ok},
          "N" => %{"bors" => :ok}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
  end

  test "full runthrough with test failure", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Tell the batcher that the test suite failed.
    # It should send out an error, and start retrying.
    Batcher.do_handle_cast({:status, {"iniNO", "ci", :error, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        comments: %{
          1 => ["# Build failed (retrying...)\n  * ci"],
          2 => ["# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Kick off the new, replacement batch.
    [batch_lo, batch_hi] = ordered_batches(proj)

    batch_lo
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_lo = Repo.get_by! Batch, id: batch_lo.id
    assert batch_lo.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{
          1 => ["# Build failed (retrying...)\n  * ci"],
          2 => ["# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Tell the batcher that the test suite failed.
    # It should out an error, and not retry
    # (because the batch has one item in it).
    Batcher.do_handle_cast({:status, {"iniN", "ci", :error, nil}}, proj.id)
    batch_lo = Repo.get! Batch, batch_lo.id
    assert batch_lo.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{
          1 => [
            "# Build failed\n  * ci",
            "# Build failed (retrying...)\n  * ci"],
          2 => ["# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Kick off the other replacement batch.
    batch_hi
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_hi = Repo.get_by! Batch, id: batch_hi.id
    assert batch_hi.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        comments: %{
          1 => [
            "# Build failed\n  * ci",
            "# Build failed (retrying...)\n  * ci"],
          2 => ["# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Tell the batcher that the test suite failed.
    # It should send out an error, and not retry
    # (because the batch has one item in it).
    Batcher.do_handle_cast({:status, {"iniO", "ci", :error, nil}}, proj.id)
    batch_hi = Repo.get! Batch, batch_hi.id
    assert batch_hi.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        comments: %{
          1 => [
            "# Build failed\n  * ci",
            "# Build failed (retrying...)\n  * ci"],
          2 => [
            "# Build failed\n  * ci",
            "# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "iniO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # There should be no more items in the queue now
    [] = Repo.all(Batch.all_for_project(proj.id, :waiting))
  end

  test "full with differing branches", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "release"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id, into_branch: "master"
    assert batch.state == 0
    # Polling at a later time kicks it off.
    # It should only kick off the first one, not the second.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == 1
    assert batch.into_branch == "master"
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Fetch the second batch.
    # Also, set off its timer,
    # so that it'll start once the first one is finished.
    {batch, batch2} = case Repo.all(Batch) do
      [batch1, batch2] ->
        if batch1.id == batch.id do
          {batch1, batch2}
        else
          {batch2, batch1}
        end
    end
    assert batch2.into_branch == "release"
    batch2
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    # Finally, finish the first batch, causing the second to start.
    Batcher.do_handle_cast({:status, {"iniN", "ci", :ok, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniN",
          "staging" => "releaseO"},
        comments: %{1 => ["# Build succeeded\n  * ci"], 2 => []},
        statuses: %{
          "iniN" => %{"bors" => :ok},
          "N" => %{"bors" => :ok},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
  end

  test "full runthrough with test timeout", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Polling at a later time causes the test to time out.
    # It should send out an error, and start retrying.
    batch
    |> Batch.changeset(%{timeout_at: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        comments: %{
          1 => ["# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Kick off the new, replacement batch.
    [batch_lo, batch_hi] = ordered_batches(proj)

    batch_lo
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_lo = Repo.get_by! Batch, id: batch_lo.id
    assert batch_lo.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{
          1 => ["# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Polling at a later time causes the test to time out.
    # It should out an error, and not retry
    # (because the batch has one item in it).
    batch_lo
    |> Batch.changeset(%{timeout_at: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_lo = Repo.get! Batch, batch_lo.id
    assert batch_lo.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        comments: %{
          1 => ["# Timed out", "# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Kick off the other replacement batch.
    batch_hi
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_hi = Repo.get_by! Batch, id: batch_hi.id
    assert batch_hi.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        comments: %{
          1 => ["# Timed out", "# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Polling at a later time causes the test to time out.
    # It should send out an error, and not retry
    # (because the batch has one item in it).
    batch_hi
    |> Batch.changeset(%{timeout_at: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_hi = Repo.get! Batch, batch_hi.id
    assert batch_hi.state == 3
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        comments: %{
          1 => ["# Timed out", "# Timed out (retrying...)"],
          2 => ["# Timed out", "# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "iniO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # There should be no more items in the queue now
    [] = Repo.all(Batch.all_for_project(proj.id, :waiting))
  end

  test "infer from .travis.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"staging.tmp" => %{".travis.yml" => ""}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    [status] = Repo.all(Status)
    assert status.identifier == "continuous-integration/travis-ci/push"
  end

  test "infer from .github/bors.toml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"staging.tmp" =>
        %{".github/bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == 0
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    [status] = Repo.all(Status)
    assert status.identifier == "ci"
  end

  test "sets patch priorities", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      into_branch: "master"}
    |> Repo.insert!()

    Batcher.handle_call({:set_priority, patch.id, 10}, nil, nil)
    assert Repo.one!(Patch).priority == 10
  end

  test "puts batches with lower priorities on hold", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})

    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    |> Repo.insert!()
    batch = %Batch{
      project_id: proj.id,
      state: 1,
      into_branch: "master"}
    |> Repo.insert!()

    %LinkPatchBatch{patch_id: patch.id, batch_id: batch.id}
    |> Repo.insert!()

    Batcher.handle_call({:set_priority, patch2.id, 10}, nil, nil)
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)

    assert Repo.one!(from b in Batch, where: b.id == ^batch.id).state == 0
    assert Repo.one!(from b in Batch, where: b.id == ^batch.id).priority == 0
    assert Repo.one!(from b in Patch, where: b.id == ^patch.id).priority == 0
    assert Repo.one!(from b in Batch, where: b.id != ^batch.id).priority == 10
  end

  test "sort_batches() handles priorities too", %{proj: proj} do
    t1 = ~N[2000-01-01 23:00:07]
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix
    t2 = ~N[2000-01-10 23:00:07]
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix
    batch = %Batch{
      project_id: proj.id,
      state: 0,
      into_branch: "master",
      last_polled: t1}
    |> Repo.insert!()

    batch2 = %Batch{
      project_id: proj.id,
      state: 0,
      into_branch: "master",
      last_polled: t2}
    |> Repo.insert!()

    batch3 = %Batch{
      project_id: proj.id,
      state: 0,
      into_branch: "master",
      priority: 10}
    |> Repo.insert!()

    sorted = Batcher.sort_batches([batch, batch2, batch3])
    assert sorted == {:waiting, [batch3, batch, batch2]}
  end

  test "posts message if patch has ci skip", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
      }})

    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      title: "[ci skip]",
      into_branch: "master"}
    |> Repo.insert!()

    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)

    state = GitHub.ServerMock.get_state()
    comments = state[{{:installation, 91}, 14}].comments[1]
    assert comments == ["Has [ci skip], bors build will time out"]
  end

  defp ordered_batches(proj) do
    Batch.all_for_project(proj.id, :waiting)
    |> join(:inner, [b], l in assoc(b, :patches))
    |> join(:inner, [_, l], patch in assoc(l, :patch))
    |> order_by([_, _, p], p.commit)
    |> preload([b, l, p], [patches: {l, patch: p}])
    |> Repo.all()
  end
end
