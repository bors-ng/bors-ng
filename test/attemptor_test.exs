defmodule Aelita2.AttemptorTest do
  use Aelita2.ModelCase

  alias Aelita2.Attempt
  alias Aelita2.Attemptor
  alias Aelita2.GitHub
  alias Aelita2.Installation
  alias Aelita2.Patch
  alias Aelita2.Project

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
    Attemptor.handle_cast({:tried, patch.id}, proj.id)
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

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Attempts start running immediately
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{ "master" => "ini", "trying" => "", "trying.tmp" => "" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "trying" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N"}
    |> Repo.insert!()
    Attemptor.handle_cast({:tried, patch.id}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN",
          "trying.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "trying" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    # Polling should not change that.
    Attemptor.handle_info(:poll, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN",
          "trying.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [] },
        files: %{ "trying" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN",
          "trying.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [ {"ci", :ok}] },
        files: %{ "trying" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }})
    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN",
          "trying.tmp" => "iniN" },
        comments: %{ 1 => [] },
        statuses: %{ "iniN" => [ {"ci", :ok}] },
        files: %{ "trying" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
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
          "trying" => "iniN",
          "trying.tmp" => "iniN" },
        comments: %{ 1 => [ "# Build succeeded\n  * ci" ] },
        statuses: %{ "iniN" => [ {"ci", :ok}] },
        files: %{ "trying" => %{ "bors.toml" => ~s/status = [ "ci" ]/ } }
      }}
  end
end
