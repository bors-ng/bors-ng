defmodule BorsNG.Database.Crash do
  @moduledoc """
  A Crash Dump from a Bors Agent.

  Allows an admin to see that a crash happened for a certain build thus
  allowing it to be reacted upon.
  """

  use BorsNG.Database.Model

  @type t :: %__MODULE__{}

  schema "crashes" do
    belongs_to :project, Project
    field :crash, :string
    field :component, :string
    timestamps()
  end

  @spec changeset(t | Ecto.Changeset.t, map) :: Ecto.Changeset.t
  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:crash, :component])
  end

  @spec all_for_project(Project.id) :: Ecto.Queryable.t
  def all_for_project(project_id) do
    from c in Crash,
      where: c.project_id == ^project_id
  end

  @spec days(integer) :: Ecto.Queryable.t
  def days(d) do
    ds = d * 60 * 60 * 24
    start = NaiveDateTime.utc_now() |> NaiveDateTime.add(-ds, :second)
    from c in Crash,
      where: c.inserted_at >= ^start
  end
end
