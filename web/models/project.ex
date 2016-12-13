defmodule Aelita2.Project do
  use Aelita2.Web, :model

  schema "projects" do
    field :repo_id, :integer
    field :type, :string
    field :name, :string
    belongs_to :users, Aelita2.User

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:repo_id, :type, :name])
    |> validate_required([:repo_id, :type, :name])
  end
end
