defmodule BorsNG.Database.LinkPatchBatch do
  @moduledoc """
  Linker table between the patches that are being run by a batch,
  and the batch itself.

  There should not be more than one running batch with the same patch,
  though once a batch fails out, other batches can take the same patch.
  """

  use BorsNG.Database.Model

  schema "link_patch_batch" do
    belongs_to :patch, Patch
    belongs_to :batch, Batch
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
