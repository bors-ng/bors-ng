defmodule BorsNG.Worker.AttemptorTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.Worker.Attemptor
  alias BorsNG.Database.Attempt
  alias BorsNG.Database.AttemptStatus
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  setup do
    inst =
      %Installation{installation_xref: 91}
      |> Repo.insert!()

    proj =
      %Project{
        installation_id: inst.id,
        repo_xref: 14,
        staging_branch: "staging",
        trying_branch: "trying"
      }
      |> Repo.insert!()

    {:ok, inst: inst, proj: proj}
  end

  def new_patch(proj, pr_xref, commit) do
    %Patch{
      project_id: proj.id,
      pr_xref: pr_xref,
      into_branch: "master",
      commit: commit
    }
    |> Repo.insert!()
  end

  def new_attempt(patch, state) do
    %Attempt{patch_id: patch.id, state: state, into_branch: "master"}
    |> Repo.insert!()
  end

  test "rejects running patches", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        commits: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }
    })

    patch = new_patch(proj, 1, nil)
    _attempt = new_attempt(patch, 0)
    Attemptor.handle_cast({:tried, patch.id, ""}, proj.id)
    state = GitHub.ServerMock.get_state()

    assert state == %{
             {{:installation, 91}, 14} => %{
               branches: %{},
               commits: %{},
               comments: %{
                 1 => ["## try\n\nAlready running a review"]
               },
               statuses: %{},
               files: %{}
             }
           }
  end

  test "infer from .travis.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{".travis.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/travis-ci/push"
  end

  test "infer from .travis.yml and appveyor.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{".travis.yml" => "", "appveyor.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    statuses = Repo.all(AttemptStatus)

    assert Enum.any?(
             statuses,
             &(&1.identifier == "continuous-integration/travis-ci/push")
           )

    assert Enum.any?(
             statuses,
             &(&1.identifier == "continuous-integration/appveyor/branch")
           )
  end

  test "infer from .appveyor.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{".appveyor.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/appveyor/branch"
  end

  test "infer from circle.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"circle.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "ci/circleci"
  end

  test "infer from jet-steps.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"jet-steps.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from jet-steps.json", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"jet-steps.json" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from codeship-steps.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"codeship-steps.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from codeship-steps.json", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"codeship-steps.json" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from .semaphore/semaphore.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{".semaphore/semaphore.yml" => ""}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/semaphoreci"
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Attempts start running immediately
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => []},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
             }
           }

    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running
    # Polling should not change that.
    Attemptor.handle_info(:poll, proj.id)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => []},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
             }
           }

    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"
        },
        commits: %{
          "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
          "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
        },
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }
    })

    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => [{"ci", :ok}]},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
             }
           }

    # Finally, an actual poll should finish it.
    attempt
    |> Attempt.changeset(%{last_polled: 0})
    |> Repo.update!()

    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :ok

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => ["## try\n\nBuild succeeded:\n  * ci"]},
               statuses: %{"iniN" => [{"ci", :ok}]},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
             }
           }
  end

  test "cancelling defuses polling", %{proj: proj} do
    # Attempts start running immediately
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => []},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
             }
           }

    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running
    # Cancel.
    Attemptor.handle_cast({:cancel, patch.id}, proj.id)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => []},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
             }
           }

    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :canceled
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"
        },
        commits: %{
          "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
          "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
        },
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }
    })

    # Polling should not change the result after cancelling.
    attempt
    |> Attempt.changeset(%{last_polled: 0})
    |> Repo.update!()

    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :canceled

    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"
        },
        commits: %{
          "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
          "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
        },
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }
    })
  end

  test "full runthrough (with wildcard)", %{proj: proj} do
    # Attempts start running immediately
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "c%" ]/}}
      }
    })

    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => []},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "c%" ]/}}
             }
           }

    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running
    # Polling should not change that.
    Attemptor.handle_info(:poll, proj.id)

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => []},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "c%" ]/}}
             }
           }

    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"
        },
        commits: %{
          "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
          "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
        },
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "c%" ]/}}
      }
    })

    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :running

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => []},
               statuses: %{"iniN" => [{"ci", :ok}]},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "c%" ]/}}
             }
           }

    # Finally, an actual poll should finish it.
    attempt
    |> Attempt.changeset(%{last_polled: 0})
    |> Repo.update!()

    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by!(Attempt, patch_id: patch.id)
    assert attempt.state == :ok

    assert GitHub.ServerMock.get_state() == %{
             {{:installation, 91}, 14} => %{
               branches: %{
                 "master" => "ini",
                 "trying" => "iniN"
               },
               commits: %{
                 "ini" => %{commit_message: "[ci skip][skip ci][skip netlify]", parents: ["ini"]},
                 "iniN" => %{commit_message: "Try #1:test", parents: ["ini", "N"]}
               },
               comments: %{1 => ["## try\n\nBuild succeeded:\n  * ci"]},
               statuses: %{"iniN" => [{"ci", :ok}]},
               files: %{"trying.tmp" => %{"bors.toml" => ~s/status = [ "c%" ]/}}
             }
           }
  end

  test "posts message if patch has ci skip", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        commits: %{},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying.tmp" => %{"circle.yml" => ""}}
      }
    })

    patch =
      %Patch{
        project_id: proj.id,
        pr_xref: 1,
        commit: "N",
        title: "[ci skip][skip ci][skip netlify]",
        into_branch: "master"
      }
      |> Repo.insert!()

    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    state = GitHub.ServerMock.get_state()
    comments = state[{{:installation, 91}, 14}].comments[1]

    assert comments == [
             "## try\n\nHas [ci skip][skip ci][skip netlify], bors build will time out"
           ]
  end
end
