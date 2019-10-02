defmodule BorsNG.Database.LinkPatchCodeOwners do

  use BorsNG.Database.Model
  
  schema "link_patch_code_owners" do
    belongs_to :patch, Patch
    belongs_to :code_owners, CodeOwners
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch_id, :code_owners_id])
    |> validate_required([:patch_id, :code_owners_id])
  end
end
  