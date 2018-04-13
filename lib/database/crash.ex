defmodule BorsNG.Database.Crash do
  @moduledoc """
  Crash dumps.
  """

  use BorsNG.Database.Model

  @type t :: %Crash{}

  schema "crashes" do
    belongs_to :project, Project
    field :crash, :string
    field :component, :string
    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:crash, :component])
  end

  def all_for_project(project_id) do
    from c in Crash,
      where: c.project_id == ^project_id
  end
end
