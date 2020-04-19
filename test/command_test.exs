defmodule BorsNG.CommandTest do
  use ExUnit.Case
  use ExUnit.Parameterized

  alias BorsNG.Command
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  doctest BorsNG.Command

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    inst =
      %Installation{installation_xref: 91}
      |> Repo.insert!()

    proj =
      %Project{
        installation_id: inst.id,
        repo_xref: 14,
        staging_branch: "staging"
      }
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
    assert [:activate] == Command.parse("bors merge")
    assert [:deactivate] == Command.parse("bors r-")
    assert [:deactivate] == Command.parse("bors merge-")
  end

  test "accept the case insensity bare command" do
    assert [{:try, ""}] == Command.parse("Bors try")
    assert [:activate] == Command.parse("Bors r+")
    assert [:activate] == Command.parse("Bors merge")
    assert [:deactivate] == Command.parse("Bors r-")
    assert [:deactivate] == Command.parse("Bors merge-")
  end

  test "accept single patch" do
    assert [{:set_is_single, true}, :activate] == Command.parse("bors r+ single on")
    assert [{:set_is_single, false}, :activate] == Command.parse("bors r+ single off")
    assert [{:set_is_single, true}] == Command.parse("bors single on")
    assert [{:set_is_single, false}] == Command.parse("bors single off")
  end

  test "do not parse single patch after try command" do
    assert [{:try, " single on"}] == Command.parse("bors try single on")
    assert [{:try, " single screwy"}] == Command.parse("bors try single screwy")
  end

  test "accept priority" do
    assert [{:set_priority, 1}, :activate] == Command.parse("bors r+ p=1")
    assert [{:set_priority, 1}, :activate] == Command.parse("bors merge p=1")

    assert [{:set_priority, 1}, {:activate_by, "me"}] ==
             Command.parse("bors r=me p=1")

    assert [{:set_priority, 1}, {:activate_by, "me"}] ==
             Command.parse("bors merge=me p=1")

    assert [{:set_priority, 1}] == Command.parse("bors p=1")
  end

  test "accept priority case insensity" do
    assert [{:set_priority, 1}, :activate] == Command.parse("Bors r+ p=1")
    assert [{:set_priority, 1}, :activate] == Command.parse("Bors merge p=1")

    assert [{:set_priority, 1}, {:activate_by, "me"}] ==
             Command.parse("Bors r=me p=1")

    assert [{:set_priority, 1}, {:activate_by, "me"}] ==
             Command.parse("Bors merge=me p=1")

    assert [{:set_priority, 1}] == Command.parse("Bors p=1")
  end

  test "accept negative priority" do
    assert [{:set_priority, -1}, :activate] == Command.parse("bors r+ p=-1")
    assert [{:set_priority, -1}, :activate] == Command.parse("bors merge p=-1")

    assert [{:set_priority, -1}, {:activate_by, "me"}] ==
             Command.parse("bors r=me p=-1")

    assert [{:set_priority, -1}, {:activate_by, "me"}] ==
             Command.parse("bors merge=me p=-1")

    assert [{:set_priority, -1}] == Command.parse("bors p=-1")
  end

  test "do not parse priority after try command" do
    assert [{:try, " p=1"}] == Command.parse("bors try p=1")
    assert [{:try, " p=screwy"}] == Command.parse("bors try p=screwy")
  end

  test "accept command with colon after it" do
    assert [{:try, ""}] == Command.parse("bors: try")
    assert [:activate] == Command.parse("bors: r+")
    assert [:activate] == Command.parse("bors: merge")
    assert [:deactivate] == Command.parse("bors: r-")
    assert [:deactivate] == Command.parse("bors: merge-")
  end

  test "accept the try command with an argument" do
    assert [{:try, "-layout"}] == Command.parse("bors try-layout")
  end

  test "accept more than one command in a single comment" do
    expected_1 = [
      {:try, ""},
      :deactivate
    ]

    command_1 = """
    bors try
    bors r-
    """

    assert expected_1 == Command.parse(command_1)

    expected_2 = [
      {:try, ""},
      :deactivate
    ]

    command_2 = """
    bors try
    bors merge-
    """

    assert expected_2 == Command.parse(command_2)
  end

  test "accept the try command with more argumentation" do
    assert [{:try, " --layout --script"}] ==
             Command.parse("bors try --layout --script")
  end

  test "do not accept the command with a prefix" do
    assert [] == Command.parse("Xbors tryZ")
  end

  test "accept bros with a valid command" do
    assert [:bros] == Command.parse("bros ping")
  end

  test "do not accept any bros without a valid command" do
    assert [] == Command.parse("bros talk")
  end

  test "command permissions" do
    assert :none == Command.required_permission_level([])
    assert :none == Command.required_permission_level([:ping])
    assert :member == Command.required_permission_level([{:try, ""}])
    assert :member == Command.required_permission_level([{:try, ""}, :ping])

    assert :reviewer ==
             Command.required_permission_level([:approve, {:try, ""}])

    assert :reviewer ==
             Command.required_permission_level([{:try, ""}, :approve])
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
      commenter: nil,
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
          1 => pr
        }
      }
    })

    {:ok, _} =
      Repo.insert(%BorsNG.Database.Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "N",
        into_branch: "master"
      })

    {:ok, commenter} =
      Repo.insert(%BorsNG.Database.User{
        user_xref: 1,
        login: "commenter"
      })

    c = %Command{
      project: proj,
      commenter: commenter,
      comment: "bors ping",
      pr_xref: 1
    }

    Command.run(c)
  end

  test_with_params "delegate+ delegates to patch creator", %{proj: proj}, fn delegate_command ->
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
        id: 2,
        login: "pr_author"
      }
    }

    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => ["bors #{delegate_command}"]},
        statuses: %{},
        pulls: %{
          1 => pr
        }
      }
    })

    {:ok, user} =
      Repo.insert(%BorsNG.Database.User{
        user_xref: 1,
        is_admin: true,
        login: "repo_owner"
      })

    {:ok, _} =
      Repo.insert(%BorsNG.Database.Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "N",
        into_branch: "master"
      })

    Repo.insert(%BorsNG.Database.LinkUserProject{
      user_id: user.id,
      project_id: proj.id
    })

    c = %Command{
      project: proj,
      commenter: user,
      comment: "bors #{delegate_command}",
      pr_xref: 1
    }

    Command.run(c)

    [p] = Repo.all(BorsNG.Database.UserPatchDelegation)
    p = Repo.preload(p, :user)
    assert p.user.user_xref == 2
  end do
    [
      {"delegate+"},
      {"d+"}
    ]
  end

  test "retry fails for non-members", %{proj: proj} do
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
        id: 2,
        login: "pr_author"
      }
    }

    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => pr
        }
      }
    })

    {:ok, commenter} =
      Repo.insert(%BorsNG.Database.User{
        user_xref: 1,
        login: "commenter"
      })

    {:ok, patch} =
      Repo.insert(%BorsNG.Database.Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "N",
        into_branch: "master"
      })

    c = %Command{
      project: proj,
      commenter: commenter,
      comment: "bors ping",
      patch: patch,
      pr_xref: 1
    }

    Command.run(c)

    c = %Command{
      project: proj,
      commenter: commenter,
      comment: "bors retry",
      patch: patch,
      pr_xref: 1
    }

    Command.run(c)

    assert %{
             {{:installation, 91}, 14} => %{
               comments: %{1 => [":lock:" <> _, _]}
             }
           } = GitHub.ServerMock.get_state()
  end

  test "retry work for members", %{proj: proj} do
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
        id: 2,
        login: "pr_author"
      }
    }

    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        pulls: %{
          1 => pr
        }
      }
    })

    {:ok, commenter} =
      Repo.insert(%BorsNG.Database.User{
        user_xref: 1,
        login: "commenter"
      })

    {:ok, patch} =
      Repo.insert(%BorsNG.Database.Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "N",
        into_branch: "master"
      })

    {:ok, _} =
      Repo.insert(%BorsNG.Database.LinkMemberProject{
        user_id: commenter.id,
        project_id: proj.id
      })

    c = %Command{
      project: proj,
      commenter: commenter,
      comment: "bors ping",
      patch: patch,
      pr_xref: 1
    }

    Command.run(c)

    c = %Command{
      project: proj,
      commenter: commenter,
      comment: "bors retry",
      patch: patch,
      pr_xref: 1
    }

    Command.run(c)

    assert %{
             {{:installation, 91}, 14} => %{
               comments: %{1 => ["pong", "pong"]}
             }
           } = GitHub.ServerMock.get_state()
  end

  test "running bros command should post brofist", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{}
      }
    })

    c = %Command{
      project: proj,
      commenter: nil,
      comment: "bros ping",
      pr_xref: 1
    }

    Command.run(c, :bros)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{},
               comments: %{1 => ["👊"]},
               statuses: %{}
             }
           }
  end

  test "command trigger is dynamically set by env" do
    old_env = System.get_env("COMMAND_TRIGGER")
    System.put_env("COMMAND_TRIGGER", "popo")

    assert [] == Command.parse("bors try")
    assert [] == Command.parse("bors r+")
    assert [] == Command.parse("bors merge")
    assert [] == Command.parse("bors r-")
    assert [] == Command.parse("bors merge-")

    assert [{:try, ""}] == Command.parse("popo try")
    assert [:activate] == Command.parse("popo r+")
    assert [:activate] == Command.parse("popo merge")
    assert [:deactivate] == Command.parse("popo r-")
    assert [:deactivate] == Command.parse("popo merge-")

    if old_env do
      System.put_env("COMMAND_TRIGGER", old_env)
    else
      System.delete_env("COMMAND_TRIGGER")
    end
  end
end
