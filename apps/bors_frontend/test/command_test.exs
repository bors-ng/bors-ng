defmodule BorsNG.CommandTest do
  use ExUnit.Case

  alias BorsNG.Command
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  doctest BorsNG.Command

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      staging_branch: "staging"}
    |> Repo.insert!()
    {:ok, inst: inst, proj: proj}
  end

  test "reject the empty string" do
    assert [] == Command.parse("")
    assert [] == Command.parse(nil)
  end

  test "reject strings without the phrase" do
    assert [] == Command.parse("doink!")
  end

  test "reject a string that merely starts out like a command" do
    assert [] == Command.parse("bors doink")
  end

  test "accept the bare command" do
    assert [{:try, ""}] == Command.parse("bors try")
    assert [:activate] == Command.parse("bors r+")
    assert [:deactivate] == Command.parse("bors r-")
  end

  test "accept command with colon after it" do
    assert [{:try, ""}] == Command.parse("bors: try")
  end

  test "accept the try command with an argument" do
    assert [{:try, "-layout"}] == Command.parse("bors try-layout")
  end

  test "accept more than one command in a single comment" do
    expected = [
      {:try, ""},
      :deactivate]
    command = """
    bors try
    bors r-
    """
    assert expected == Command.parse(command)
  end

  test "accept the try command with more argumentation" do
    assert [{:try, " --layout --script"}] ==
      Command.parse("bors try --layout --script")
  end

  test "do not accept the command with a prefix" do
    assert [] == Command.parse("Xbors tryZ")
  end

  test "running ping command should post comment", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{}
      }
    })

    c = %Command{
      project: proj,
      commenter: "commenter",
      comment: "bors ping",
      pr_xref: 1
    }
    Command.run(c, :ping)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => ["pong"]},
        statuses: %{}
      }
    }
  end

  test "running ping when commenter is not reviewer", %{proj: proj} do
    pr = %BorsNG.GitHub.Pr{
      number: 1,
      title: "Test",
      body: "Mess",
      state: :open,
      base_ref: "master",
      head_sha: "00000001",
      head_ref: "update",
      base_repo_id: 13,
      head_repo_id: 13,
      user: %{
        id: 1,
        login: "user"
      }
    }

    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => ["bors ping"]},
        statuses: %{},
        pulls: %{
          1 => pr,
        },
      }
    })

    {:ok, _} = Repo.insert(%BorsNG.Database.Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      into_branch: "master"
    })

    c = %Command{
      project: proj,
      commenter: "commenter",
      comment: "bors ping",
      pr_xref: 1
    }

    Command.run(c)
  end
end
