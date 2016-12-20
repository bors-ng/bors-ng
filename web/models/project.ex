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

  def by_owner(owner_id) do
    Aelita2.Repo.all(from l in LinkUserProject,
      where: l.user_id == ^owner_id,
      preload: :project)
    |> Enum.map(&(&1.project))
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
