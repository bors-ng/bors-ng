defmodule BorsNG.Worker.TestCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias BorsNG.Database
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BorsNG.Database.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(BorsNG.Database.Repo, {:shared, self()})
    end

    :ok
  end
end
