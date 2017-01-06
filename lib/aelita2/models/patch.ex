defmodule Aelita2.Patch do
  use Aelita2.Web, :model

  alias Aelita2.Batch
  alias Aelita2.LinkPatchBatch
  alias Aelita2.LinkUserProject
  alias Aelita2.Patch

  schema "patches" do
    belongs_to :project, Aelita2.Project
    field :pr_xref, :integer
    field :title, :string
    field :body, :string
    field :commit, :string
    field :open, :boolean, default: true
    belongs_to :author, Aelita2.User
    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:pr_xref, :title, :body, :commit, :author_id, :project_id, :author_id, :open])
  end

  def all_for_batch(batch_id) do
    from p in Patch,
      join: l in LinkPatchBatch, on: l.patch_id == p.id,
      where: l.batch_id == ^batch_id
  end

  defp all_links_not_err() do
    err = Batch.numberize_state(:err)
    from l in LinkPatchBatch,
      join: b in Batch, on: (l.batch_id == b.id and b.state != ^err)
  end

  def all(:awaiting_review) do
    all = all_links_not_err()
    from p in Patch,
      left_join: l in subquery(all), on: l.patch_id == p.id,
      where: is_nil(l.batch_id),
      where: p.open == true
  end

  def all_for_project(project_id, :awaiting_review) do
    from p in Patch.all(:awaiting_review),
      where: p.project_id == ^project_id
  end

  def all_for_user(user_id, :awaiting_review) do
    from p in Patch.all(:awaiting_review),
      preload: :project,
      join: lu in LinkUserProject, on: lu.project_id == p.project_id,
      where: lu.user_id == ^user_id
  end
end
