defmodule BorsNG.Database.LinkPatchCodeOwnerReviewer do

  use BorsNG.Database.Model
  
  schema "link_patch_code_owner_reviewers" do
    belongs_to :patch, Patch
    belongs_to :code_owner_reviewer, CodeOwnerReviewer
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch_id, :code_owner_reviewer_id])
    |> validate_required([:patch_id, :code_owner_reviewer_id])
  end
end
  