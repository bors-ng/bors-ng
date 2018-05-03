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
        commits: %{},
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
        commits: %{},
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

  test "cancel a running batch with one patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
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
        commits: %{},
        comments: %{
          1 => ["# Canceled"]
          },
        statuses: %{"N" => %{"bors" => :error}},
        files: %{}
      }}
    assert :canceled == Repo.get(Batch, batch.id).state
  end

  test "cancel a running batch with two patches", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
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
      commit: "P",
      into_branch: "master"}
    |> Repo.insert!()
    batch = %Batch{
      project_id: proj.id,
      state: 1,
      into_branch: "master"}
    |> Repo.insert!()
    %LinkPatchBatch{
      patch_id: patch.id,
      batch_id: batch.id,
      reviewer: "nobody"}
    |> Repo.insert!()
    %LinkPatchBatch{
      patch_id: patch2.id,
      batch_id: batch.id,
      reviewer: "nobody"}
    |> Repo.insert!()
    Batcher.handle_cast({:cancel, patch.id}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
        comments: %{
          1 => ["# Canceled"],
          2 => ["# Canceled (will resume)"]},
        statuses: %{
          "N" => %{"bors" => :error},
          "P" => %{"bors" => :error}},
        files: %{}
      }}
    assert :canceled == Repo.get(Batch, batch.id).state
    link2 = Repo.one!(from l in LinkPatchBatch, where: l.batch_id != ^batch.id)
    assert link2.patch_id == patch2.id
  end

  test "ignore cancel on not-running patch", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
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
        commits: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }}
  end

  test "rejects running patches", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
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
        commits: %{},
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
        commits: %{},
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
        commits: %{},
        comments: %{
          1 => [":-1: Rejected by label"]},
        labels: %{1 => ["no"]},
        statuses: %{"Z" => %{}},
        files: %{"Z" => %{"bors.toml" =>
          ~s/status = [ "ci" ]\nblock_labels = [ "no" ]/}},
      }}
  end

  test "rejects a patch with a bad PR status", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
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
        commits: %{},
        comments: %{
          1 => [":-1: Rejected by PR status"]},
        statuses: %{"Z" => %{"cn" => :error}},
        files: %{"Z" => %{"bors.toml" =>
          ~s/status = [ "ci" ]\npr_status = [ "cn" ]/}},
      }}
  end

  test "rejects a patch with a requested changes", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"Z" => %{"cn" => :ok}},
        reviews: %{1 => %{"APPROVED" => 0, "CHANGES_REQUESTED" => 1}},
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
        commits: %{},
        comments: %{
          1 => [":-1: Rejected by code reviews"]},
        statuses: %{"Z" => %{"cn" => :ok}},
        files: %{"Z" => %{"bors.toml" =>
                           ~s/status = [ "ci" ]\npr_status = [ "cn" ]/}},
        reviews: %{1 => %{"APPROVED" => 0, "CHANGES_REQUESTED" => 1}},
      }}
  end

  test "rejects a patch with too few approved reviews", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"Z" => %{"cn" => :ok}},
        reviews: %{1 => %{"APPROVED" => 0, "CHANGES_REQUESTED" => 0}},
        files: %{"Z" => %{"bors.toml" =>
                           ~s"""
                             status = [ "ci" ]
                             pr_status = [ "cn" ]
                             required_approvals = 1
                             """}},
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
        commits: %{},
        comments: %{
          1 => [":-1: Rejected by too few approved reviews"]},
        statuses: %{"Z" => %{"cn" => :ok}},
        files: %{"Z" => %{"bors.toml" =>
                           ~s"""
                             status = [ "ci" ]
                             pr_status = [ "cn" ]
                             required_approvals = 1
                             """}},
        reviews: %{1 => %{"APPROVED" => 0, "CHANGES_REQUESTED" => 0}},
      }}
    # When preflight checks reject a patch, no batch should be created!
    assert [] == Repo.all(Batch)
  end

  test "accepts a patch with approvals", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"Z" => %{"cn" => :ok}},
        reviews: %{1 => %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0}},
        files: %{"Z" => %{"bors.toml" =>
                           ~s"""
                             status = [ "ci" ]
                             pr_status = [ "cn" ]
                             required_approvals = 1
                             """}},
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
        commits: %{},
        comments: %{
          1 => []},
        statuses: %{"Z" => %{"bors" => :running, "cn" => :ok}},
        files: %{"Z" => %{"bors.toml" =>
                           ~s"""
                             status = [ "ci" ]
                             pr_status = [ "cn" ]
                             required_approvals = 1
                             """}},
        reviews: %{1 => %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0}},
      }}
  end

  test "missing bors.toml", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
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
        commits: %{},
        comments: %{1 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{}
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at the same time doesn't change that.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini",
          "staging" => ""},
        commits: %{
          "ini" => %{
            commit_message: "[ci skip]",
            parents: ["ini"]}},
        comments: %{1 => ["# Configuration problem\nbors.toml: not found"]},
        statuses: %{"N" => %{"bors" => :error}},
        files: %{}
      }}
  end

  test "full runthrough (with zero patches)", %{proj: proj} do
    # Create a zero-patch batch in a "waiting" state
    # This isn't normally possible through the user interface,
    # but if the patch is canceled, but the report comment fails
    # this situation can emerged
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{},
        statuses: %{"ini" => %{}},
        files: %{"staging.tmp" => %{
          "bors.toml" =>
            ~s"""
              status = [ "ci" ]
              [unstable]
              allow-empty-batches = true
            """}},
      }})
    %Batch{
      project_id: proj.id,
      commit: "ini",
      state: :waiting,
      last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds),
      priority: 1,
      into_branch: "master"}
    |> Repo.insert!()
    # Polling at the same time doesn't change that.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "ini"},
        commits: %{
          "ini" => %{
            commit_message: "Merge\n\n\n",
            parents: ["ini"]}},
        comments: %{},
        statuses: %{"ini" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{
          "bors.toml" =>
            ~s"""
              status = [ "ci" ]
              [unstable]
              allow-empty-batches = true
            """}},
      }}
    # Polling again should change nothing.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    # Force-polling again should still change nothing.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "ini"},
        commits: %{
          "ini" => %{
            commit_message: "Merge\n\n\n",
            parents: ["ini"]}},
        comments: %{},
        statuses: %{"ini" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{
          "bors.toml" =>
            ~s"""
              status = [ "ci" ]
              [unstable]
              allow-empty-batches = true
            """}},
      }}
    # Mark the CI as having finished.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "ini"},
        commits: %{
          "ini" => %{
            commit_message: "Merge\n\n\n",
            parents: ["ini"]}},
        comments: %{},
        statuses: %{
          "ini" => %{"ci" => :ok, "bors" => :running}},
        files: %{"staging.tmp" => %{
          "bors.toml" =>
            ~s"""
              status = [ "ci" ]
              [unstable]
              allow-empty-batches = true
            """}},
      }})
    # Finally, an actual poll should finish it.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "ini"},
        commits: %{
          "ini" => %{
            commit_message: "Merge\n\n\n",
            parents: ["ini"]}},
        comments: %{},
        statuses: %{
          "ini" => %{"bors" => :ok, "ci" => :ok}},
        files: %{"staging.tmp" => %{
          "bors.toml" =>
            ~s"""
              status = [ "ci" ]
              [unstable]
              allow-empty-batches = true
            """}},
      }}
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
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
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}, "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at the same time doesn't change that.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}, "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      }}
    # Polling again should change nothing.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    # Force-polling again should still change nothing.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}, "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      }}
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => []},
        statuses: %{
          "iniN" => %{"ci" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      }})
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => []},
        statuses: %{
          "iniN" => %{"ci" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      }}
    # Finally, an actual poll should finish it.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniN",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => ["# Build succeeded\n  * ci"]},
        statuses: %{
          "iniN" => %{"bors" => :ok, "ci" => :ok},
          "N" => %{"bors" => :ok}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      }}
  end

  test "merge conflict", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => %{}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      },
      :merge_conflict => 0,
    })
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    |> Repo.insert!()
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at the same time doesn't change that.
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => ""},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]}},
        comments: %{1 => ["# Merge conflict"]},
        statuses: %{"N" => %{"bors" => :error}, "iniN" => %{}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [
          %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
        ]},
      },
      :merge_conflict => 0,
    }
  end

  test "full runthrough and continue", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Submit the second one.
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
    assert batch.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniN",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{commit_message: "[ci skip]", parents: ["iniN"]},
          "iniNO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["iniN", "O"]}},
        comments: %{1 => ["# Build succeeded\n  * ci"], 2 => []},
        statuses: %{
          "iniN" => %{"bors" => :ok},
          "N" => %{"bors" => :ok},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
  end

  test "full runthrough with priority putting one on hold", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["ini", "O"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "iniN" => %{"bors" => :running},
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Finally, finish the higher-priority, second batch.
    Batcher.do_handle_cast({:status, {"iniO", "ci", :ok, nil}}, proj.id)
    batch2 = Repo.get! Batch, batch2.id
    assert batch2.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniO",
          "staging" => "iniO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["ini", "O"]}},
        comments: %{2 => ["# Build succeeded\n  * ci"], 1 => []},
        statuses: %{
          "iniN" => %{"bors" => :running},
          "iniO" => %{"bors" => :ok},
          "O" => %{"bors" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{commit_message: "[ci skip]", parents: ["iniO"]},
          "iniON" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["iniO", "N"]}},
        comments: %{2 => ["# Build succeeded\n  * ci"], 1 => []},
        statuses: %{
          "iniN" => %{"bors" => :running},
          "iniO" => %{"bors" => :ok},
          "O" => %{"bors" => :ok},
          "N" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Finish the first one, since the higher-priority item is past it now
    Batcher.do_handle_cast({:status, {"iniON", "ci", :ok, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniON",
          "staging" => "iniON"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{commit_message: "[ci skip]", parents: ["iniO"]},
          "iniON" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["iniO", "N"]}},
        comments: %{
          2 => ["# Build succeeded\n  * ci"],
          1 => ["# Build succeeded\n  * ci"]},
        statuses: %{
          "iniN" => %{"bors" => :running},
          "iniON" => %{"bors" => :ok},
          "iniO" => %{"bors" => :ok},
          "O" => %{"bors" => :ok},
          "N" => %{"bors" => :ok}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
  end

  test "full runthrough with test failure", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Tell the batcher that the test suite failed.
    # It should send out an error, and start retrying.
    Batcher.do_handle_cast({:status, {"iniNO", "ci", :error, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]}},
        comments: %{
          1 => ["# Build failed (retrying...)\n  * ci"],
          2 => ["# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Kick off the new, replacement batch.
    [batch_lo, batch_hi] = ordered_batches(proj)

    batch_lo
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_lo = Repo.get_by! Batch, id: batch_lo.id
    assert batch_lo.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{
          1 => ["# Build failed (retrying...)\n  * ci"],
          2 => ["# Build failed (retrying...)\n  * ci"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Tell the batcher that the test suite failed.
    # It should out an error, and not retry
    # (because the batch has one item in it).
    Batcher.do_handle_cast({:status, {"iniN", "ci", :error, nil}}, proj.id)
    batch_lo = Repo.get! Batch, batch_lo.id
    assert batch_lo.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
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
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Kick off the other replacement batch.
    batch_hi
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_hi = Repo.get_by! Batch, id: batch_hi.id
    assert batch_hi.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["ini", "O"]}},
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
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Tell the batcher that the test suite failed.
    # It should send out an error, and not retry
    # (because the batch has one item in it).
    Batcher.do_handle_cast({:status, {"iniO", "ci", :error, nil}}, proj.id)
    batch_hi = Repo.get! Batch, batch_hi.id
    assert batch_hi.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["ini", "O"]}},
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
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # There should be no more items in the queue now
    [] = Repo.all(Batch.all_for_project(proj.id, :waiting))
  end

  test "full with differing branches", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id, into_branch: "master"
    assert batch.state == :waiting
    # Polling at a later time kicks it off.
    # It should only kick off the first one, not the second.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == :running
    assert batch.into_branch == "master"
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
    assert batch.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniN",
          "staging" => "releaseO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "release" => %{commit_message: "[ci skip]", parents: ["release"]},
          "releaseO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["release", "O"]}},
        comments: %{1 => ["# Build succeeded\n  * ci"], 2 => []},
        statuses: %{
          "iniN" => %{"bors" => :ok},
          "N" => %{"bors" => :ok},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
  end

  test "full runthrough showing PR sorting", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "abcd", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "c", author_email: "g"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "ef90", author_name: "d", author_email: "h"}]},
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
    Batcher.handle_cast({:reviewed, patch2.id, "rvr"}, proj.id)
    Batcher.handle_cast({:reviewed, patch.id, "rvr"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "abcd", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "c", author_email: "g"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "ef90", author_name: "d", author_email: "h"}]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id, into_branch: "master"
    assert batch.state == :waiting
    # Polling at a later time kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == :running
    assert batch.into_branch == "master"
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>" <>
              "\nCo-authored-by: c <g>\nCo-authored-by: d <h>\n",
            parents: ["ini", "N", "O"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "abcd", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "c", author_email: "g"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "ef90", author_name: "d", author_email: "h"}]},
      }}
    # Finally, finish the batch.
    Batcher.do_handle_cast({:status, {"iniNO", "ci", :ok, nil}}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == :ok
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "iniNO",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>" <>
              "\nCo-authored-by: c <g>\nCo-authored-by: d <h>\n",
            parents: ["ini", "N", "O"]}},
        comments: %{
          1 => ["# Build succeeded\n  * ci"],
          2 => ["# Build succeeded\n  * ci"]
        },
        statuses: %{
          "iniNO" => %{"bors" => :ok},
          "N" => %{"bors" => :ok},
          "O" => %{"bors" => :ok}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "abcd", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "c", author_email: "g"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"},
            %GitHub.Commit{sha: "ef90", author_name: "a", author_email: "e"},
            %GitHub.Commit{sha: "ef90", author_name: "d", author_email: "h"}]},
      }}
  end

  test "full runthrough with test timeout", %{proj: proj} do
    # Projects are created with a "waiting" state
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
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
        commits: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :waiting
    # Polling at a later time (yeah, I'm setting the clock back to do it)
    # kicks it off.
    batch
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get_by! Batch, project_id: proj.id
    assert batch.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]}},
        comments: %{1 => [], 2 => []},
        statuses: %{"N" => %{"bors" => :running}, "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Polling at a later time causes the test to time out.
    # It should send out an error, and start retrying.
    batch
    |> Batch.changeset(%{timeout_at: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch = Repo.get! Batch, batch.id
    assert batch.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniNO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]}},
        comments: %{
          1 => ["# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Kick off the new, replacement batch.
    [batch_lo, batch_hi] = ordered_batches(proj)

    batch_lo
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_lo = Repo.get_by! Batch, id: batch_lo.id
    assert batch_lo.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{
          1 => ["# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "N" => %{"bors" => :running},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Polling at a later time causes the test to time out.
    # It should out an error, and not retry
    # (because the batch has one item in it).
    batch_lo
    |> Batch.changeset(%{timeout_at: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_lo = Repo.get! Batch, batch_lo.id
    assert batch_lo.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniN"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]}},
        comments: %{
          1 => ["# Timed out", "# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Kick off the other replacement batch.
    batch_hi
    |> Batch.changeset(%{last_polled: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_hi = Repo.get_by! Batch, id: batch_hi.id
    assert batch_hi.state == :running
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["ini", "O"]}},
        comments: %{
          1 => ["# Timed out", "# Timed out (retrying...)"],
          2 => ["# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :running}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # Polling at a later time causes the test to time out.
    # It should send out an error, and not retry
    # (because the batch has one item in it).
    batch_hi
    |> Batch.changeset(%{timeout_at: 0})
    |> Repo.update!()
    Batcher.handle_info({:poll, :once}, proj.id)
    batch_hi = Repo.get! Batch, batch_hi.id
    assert batch_hi.state == :error
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "staging" => "iniO"},
        commits: %{
          "ini" => %{commit_message: "[ci skip]", parents: ["ini"]},
          "iniNO" => %{
            commit_message: "Merge #1 #2\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\nCo-authored-by: b <f>\n",
            parents: ["ini", "N", "O"]},
          "iniN" => %{
            commit_message: "Merge #1\n\n1:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: a <e>\n",
            parents: ["ini", "N"]},
          "iniO" => %{
            commit_message: "Merge #2\n\n2:  r=rvr a=[unknown]\n\n\n" <>
              "\nCo-authored-by: b <f>\n",
            parents: ["ini", "O"]}},
        comments: %{
          1 => ["# Timed out", "# Timed out (retrying...)"],
          2 => ["# Timed out", "# Timed out (retrying...)"]},
        statuses: %{
          "iniNO" => %{"bors" => :error},
          "iniN" => %{"bors" => :error},
          "iniO" => %{"bors" => :error},
          "N" => %{"bors" => :error},
          "O" => %{"bors" => :error}},
        files: %{"staging.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1234", author_name: "a", author_email: "e"}],
          2 => [
            %GitHub.Commit{sha: "5678", author_name: "b", author_email: "f"}]},
      }}
    # There should be no more items in the queue now
    [] = Repo.all(Batch.all_for_project(proj.id, :waiting))
  end

  test "infer from .travis.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"staging.tmp" => %{".travis.yml" => ""}},
        pr_commits: %{1 => []},
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
    assert batch.state == :waiting
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
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"staging.tmp" =>
        %{".github/bors.toml" => ~s/status = [ "ci" ]/}},
        pr_commits: %{1 => [], 2 => []},
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
    assert batch.state == :waiting
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
        commits: %{},
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
        commits: %{},
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

    assert Repo.one!(from b in Batch,
      where: b.id == ^batch.id).state == :waiting
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
      state: :waiting,
      into_branch: "master",
      last_polled: t1}
    |> Repo.insert!()

    batch2 = %Batch{
      project_id: proj.id,
      state: :waiting,
      into_branch: "master",
      last_polled: t2}
    |> Repo.insert!()

    batch3 = %Batch{
      project_id: proj.id,
      state: :waiting,
      into_branch: "master",
      priority: 10}
    |> Repo.insert!()

    sorted = Batcher.sort_batches([batch, batch2, batch3])
    assert sorted == {:waiting, [batch3, batch, batch2]}
  end

  test "gather_co_authors() collects unique commit authors", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => [], 2 => []},
        statuses: %{},
        files: %{},
        pr_commits: %{
          1 => [
            %GitHub.Commit{sha: "1", author_name: "Foo", author_email: "foo"},
            %GitHub.Commit{sha: "2", author_name: "Bar", author_email: "bar"}],
          2 => [
            %GitHub.Commit{sha: "3", author_name: "Bar", author_email: "other"},
            %GitHub.Commit{sha: "4", author_name: "Foo", author_email: "foo"}],
        },
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"}
    patch2 = %Patch{
      project_id: proj.id,
      pr_xref: 2,
      commit: "O",
      into_branch: "master"}
    batch = %Batch{
      project: proj,
      state: 0,
      into_branch: "master"}
    link = %LinkPatchBatch{patch: patch, batch: batch}
    link2 = %LinkPatchBatch{patch: patch2, batch: batch}

    assert Batcher.gather_co_authors(batch, [link, link2]) == [
      "Foo <foo>",
      "Bar <bar>",
      "Bar <other>"]
  end

  test "posts message if patch has ci skip", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "staging" => "", "staging.tmp" => ""},
        commits: %{},
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
