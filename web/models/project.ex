defmodule Aelita2.Project do
  use Aelita2.Web, :model

  schema "projects" do
    field :repo_id, :integer
    field :name, :string
    belongs_to :installation, Aelita2.Installation

    timestamps()
  end

  def by_owner(owner) do
    from p in "projects",
      select: %{name: p.name, id: p.id},
      where: p.owner == ^owner
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:repo_id, :name])
    |> validate_required([:repo_id, :name])
  end
end
