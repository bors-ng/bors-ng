defmodule Aelita2.Installation do
  use Aelita2.Web, :model

  schema "installations" do
    field :installation_id, :integer

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
