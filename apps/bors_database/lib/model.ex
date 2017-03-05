defmodule BorsNG.Database.Model do
  @moduledoc """
  A module that keeps using definitions for models.

  This can be used as:

      use BorsNG.Database.Model
  """

  # Do NOT define functions inside the quoted expression.

  @doc """
  When used, add common imports for models.
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      alias BorsNG.Database
      alias BorsNG.Database.Attempt
      alias BorsNG.Database.AttemptStatus
      alias BorsNG.Database.Batch
      alias BorsNG.Database.Installation
      alias BorsNG.Database.LinkPatchBatch
      alias BorsNG.Database.LinkUserProject
      alias BorsNG.Database.Patch
      alias BorsNG.Database.Project
      alias BorsNG.Database.Status
      alias BorsNG.Database.User
    end
  end
end
