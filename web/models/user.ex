defmodule Aelita2.User do
  use Aelita2.Web, :model

  schema "users" do
    field :user_id, :integer
    field :login, :string
    field :type, :string

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:user_id, :login, :type])
    |> validate_required([:user_id, :login, :type])
  end
end
