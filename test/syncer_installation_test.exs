import Ecto
import Ecto.Query

defmodule BorsNG.Worker.SyncerInstallationTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.GitHub
  alias BorsNG.Database.Project
  alias BorsNG.Worker.SyncerInstallation

  test "syncing nothing does nothing" do
    repos = []
    projects = []
    result = SyncerInstallation.plan_synchronize(true, repos, projects)
    assert result == []
  end

  test "syncing the same thing does nothing" do
    repos = [
      %GitHub.Repo{id: 1, name: "me", owner: nil, private: false}
    ]

    projects = [
      %Project{id: 2, repo_xref: 1, name: "me"}
    ]

    result = SyncerInstallation.plan_synchronize(true, repos, projects)
    assert [{:sync, %{id: 2}}] = result
  end

  test "syncing a removal does something" do
    repos = []

    projects = [
      %Project{id: 2, repo_xref: 1, name: "me"}
    ]

    result = SyncerInstallation.plan_synchronize(true, repos, projects)

    assert result == [
             {:remove, %Project{id: 2, repo_xref: 1, name: "me"}}
           ]
  end

  test "syncing an add does something" do
    repos = [
      %GitHub.Repo{id: 1, name: "me", owner: nil, private: false}
    ]

    projects = []
    result = SyncerInstallation.plan_synchronize(true, repos, projects)

    assert result == [
             {:add, %GitHub.Repo{id: 1, name: "me", owner: nil, private: false}}
           ]
  end

  test "syncing unrelated repos works" do
    repos = [
      %GitHub.Repo{id: 1, name: "me", owner: nil, private: false}
    ]

    projects = [
      %Project{id: 2, repo_xref: 2, name: "me"}
    ]

    result = SyncerInstallation.plan_synchronize(true, repos, projects)

    assert result == [
             {:add, %GitHub.Repo{id: 1, name: "me", owner: nil, private: false}},
             {:remove, %Project{id: 2, repo_xref: 2, name: "me"}}
           ]
  end
end
