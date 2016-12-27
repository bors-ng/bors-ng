defmodule Aelita2.LinkPatchBatch do
  use Aelita2.Web, :model

  schema "link_patch_batch" do
    belongs_to :patch, Aelita2.Patch
    belongs_to :batch, Aelita2.Batch
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch_id, :batch_id])
    |> validate_required([:patch_id, :batch_id])
  end
end
