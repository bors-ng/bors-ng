defmodule BorsNG.AttemptorTest do
  use BorsNG.ConnCase

  alias BorsNG.Attemptor
  alias BorsNG.Database.Attempt
  alias BorsNG.Database.AttemptStatus
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  setup do
    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      master_branch: "master",
      staging_branch: "staging",
      trying_branch: "trying"}
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
    _attempt = %Attempt{patch_id: patch.id, state: 0, patch_id: patch.id}
    |> Repo.insert!()
    Attemptor.handle_cast({:tried, patch.id, ""}, proj.id)
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

  test "infer from .travis.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{".travis.yml" => ""}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/travis-ci/push"
  end

  test "infer from .travis.yml and appveyor.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{".travis.yml" => "", "appveyor.yml" => ""}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    statuses = Repo.all(AttemptStatus)
    assert Enum.any?(statuses,
      &(&1.identifier == "continuous-integration/travis-ci/push"))
    assert Enum.any?(statuses,
      &(&1.identifier == "continuous-integration/appveyor/branch"))
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Attempts start running immediately
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    # Polling should not change that.
    Attemptor.handle_info(:poll, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Finally, an actual poll should finish it.
    attempt
    |> Attempt.changeset(%{last_polled: 0})
    |> Repo.update!()
    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => ["# Build succeeded\n  * ci"]},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
  end
end
