defmodule BorsNG.Database.UserPatchDelegation do
  @moduledoc """
  The connection between a patch and users that have been
  delegated the permission to approve it.
  """

  use BorsNG.Database.Model

  schema "user_patch_delegations" do
    belongs_to(:user, User)
    belongs_to(:patch, Patch)
    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:user_id, :patch_id])
    |> validate_required([:user_id, :patch_id])
    |> unique_constraint(
      :user_id,
      name: :user_patch_delegation_user_id_patch_id_index
    )
  end
end
