defmodule Aelita2.Patch do
  use Aelita2.Web, :model

  alias Aelita2.Patch

  schema "patches" do
    belongs_to :project, Aelita2.Project
    belongs_to :batch, Aelita2.Batch
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
    |> cast(params, [:pr_xref, :title, :body, :commit, :author_id, :project_id, :batch_id, :author_id])
  end

  def all_for_batch(batch_id) do
    from(p in Patch, where: p.batch_id == ^batch_id)
  end

  def unbatched() do
    from(p in Patch, where: is_nil(p.batch_id))
  end
end
