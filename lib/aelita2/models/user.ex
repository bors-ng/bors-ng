defmodule Aelita2.User do
  use Aelita2.Web, :model

  alias Aelita2.Project
  alias Aelita2.LinkUserProject
  alias Aelita2.User

  schema "users" do
    field :user_xref, :integer
    field :login, :string
    many_to_many :projects, Project, join_through: LinkUserProject

    timestamps()
  end

  def by_project(project_id) do
    from u in User,
      join: l in LinkUserProject, on: l.project_id == ^project_id and u.id == l.user_id
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:user_xref, :login])
    |> validate_required([:user_xref, :login])
  end
end
