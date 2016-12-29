defmodule Aelita2.Patch do
  use Aelita2.Web, :model

  alias Aelita2.Batch
  alias Aelita2.LinkPatchBatch
  alias Aelita2.Patch

  schema "patches" do
    belongs_to :project, Aelita2.Project
    field :pr_xref, :integer
    field :title, :string
    field :body, :string
    field :commit, :string
    belongs_to :author, Aelita2.User
    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:pr_xref, :title, :body, :commit, :author_id, :project_id, :author_id])
  end

  def all_for_batch(batch_id) do
    from p in Patch,
      join: l in LinkPatchBatch, on: l.patch_id == p.id,
      where: l.batch_id == ^batch_id
  end

  def all_for_project(project_id, :awaiting_review) do
    err = Batch.numberize_state(:err)
    from p in Patch,
      left_join: l in LinkPatchBatch, on: l.patch_id == p.id,
      left_join: b in Batch, on: l.batch_id == b.id,
      where: p.project_id == ^project_id,
      where: is_nil(b.state) or b.state == ^err
  end
end
