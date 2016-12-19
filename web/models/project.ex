defmodule Aelita2.Project do
  use Aelita2.Web, :model

  alias Aelita2.LinkUserProject
  alias Aelita2.User

  schema "projects" do
    field :repo_xref, :integer
    field :name, :string
    belongs_to :installation, Aelita2.Installation
    many_to_many :users, User, join_through: LinkUserProject

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
    |> cast(params, [:repo_xref, :name])
    |> validate_required([:repo_xref, :name])
  end
end
