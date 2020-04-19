defmodule BorsNG.Database.LinkPatchBatch do
  @moduledoc """
  Linker table between the patches that are being run by a batch,
  and the batch itself.

  There should not be more than one running batch with the same patch,
  though once a batch fails out, other batches can take the same patch.
  """

  use BorsNG.Database.Model

  schema "link_patch_batch" do
    belongs_to(:patch, Patch)
    belongs_to(:batch, Batch)
    field(:reviewer, :string)
  end

  def from_batch(batch_id) do
    from(l in LinkPatchBatch,
      preload: [:patch, {:patch, :author}],
      where: l.batch_id == ^batch_id
    )
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch_id, :batch_id, :reviewer])
    |> validate_required([:patch_id, :batch_id, :reviewer])
    |> unique_constraint(
      :patch_id,
      name: :link_patch_batch_patch_id_batch_id_index
    )
  end
end
