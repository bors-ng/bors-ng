defmodule BorsNG.Database.Context.LoggingTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.Context.Logging
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.User

  setup do
    installation =
      Repo.insert!(%Installation{
        installation_xref: 31
      })

    project =
      Repo.insert!(%Project{
        installation_id: installation.id,
        repo_xref: 13,
        name: "example/project"
      })

    user =
      Repo.insert!(%User{
        login: "lilac"
      })

    patch =
      Repo.insert!(%Patch{
        project: project
      })

    {:ok, project: project, user: user, patch: patch}
  end

  test "most recent command", params do
    %{patch: patch, user: user} = params
    Logging.log_cmd(patch, user, :cmd1)
    Logging.log_cmd(patch, user, :cmd2)
    user_id = user.id
    assert {%User{id: ^user_id}, :cmd2} = Logging.most_recent_cmd(patch)
  end

  test "most recent command should exclude retry", params do
    %{patch: patch, user: user} = params
    Logging.log_cmd(patch, user, :cmd1)
    Logging.log_cmd(patch, user, :retry)
    user_id = user.id
    assert {%User{id: ^user_id}, :cmd1} = Logging.most_recent_cmd(patch)
  end
end
