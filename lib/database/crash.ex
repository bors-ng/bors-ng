defmodule BorsNG.Database.Crash do
  @moduledoc """
  Records of the 
  Corresponds to a pull request in GitHub.

  A closed patch may not be r+'ed,
  nor can a patch associated with a completed batch be r+'ed again,
  though a patch may be merged and r+'ed at the same time.
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
