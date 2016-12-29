defmodule Aelita2.Patch do
  use Aelita2.Web, :model

  alias Aelita2.Patch
  alias Aelita2.LinkPatchBatch

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
    from l in LinkPatchBatch,
      join: p in assoc(l, :patch),
      where: l.batch_id == ^batch_id,
      select: struct(p, [:id, :project_id, :pr_xref, :title, :body, :commit, :author_id])
  end

  def unbatched() do
    from p in Patch, where: p.pr_xref != 0
  end
end
