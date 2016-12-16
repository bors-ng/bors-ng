defmodule Aelita2.User do
  use Aelita2.Web, :model

  schema "users" do
    field :user_id, :integer
    field :login, :string
    many_to_many :projects, Aelita2.Project, join_through: "link_user_project"

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:user_id, :login])
    |> validate_required([:user_id, :login])
  end
end
