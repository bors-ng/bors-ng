defmodule BorsNG.Database.Patch do
  @moduledoc """
  Corresponds to a pull request in GitHub.

  A closed patch may not be r+'ed,
  nor can a patch associated with a completed batch be r+'ed again,
  though a patch may be merged and r+'ed at the same time.
  """

  use BorsNG.Database.Model

  @type t :: %__MODULE__{}
  @type id :: pos_integer

  schema "patches" do
    belongs_to(:project, Project)
    field(:into_branch, :string)
    field(:pr_xref, :integer)
    field(:title, :string)
    field(:body, :string)
    field(:commit, :string)
    field(:open, :boolean, default: true)
    field(:priority, :integer, default: 0)
    field(:is_single, :boolean, default: false)
    belongs_to(:author, User)
    timestamps()
  end

  @spec changeset(t | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [
      :pr_xref,
      :title,
      :body,
      :commit,
      :project_id,
      :author_id,
      :open,
      :into_branch,
      :priority,
      :is_single
    ])
    |> unique_constraint(:pr_xref, name: :patches_pr_xref_index)
  end

  @spec all_for_batch(Batch.id()) :: Ecto.Queryable.t()
  def all_for_batch(batch_id) do
    from(p in Patch,
      join: l in LinkPatchBatch,
      on: l.patch_id == p.id,
      where: l.batch_id == ^batch_id,
      order_by: [desc: p.pr_xref]
    )
  end

  @spec all_links_not_err() :: Ecto.Queryable.t()
  defp all_links_not_err do
    from(l in LinkPatchBatch,
      join: b in Batch,
      on: l.batch_id == b.id and b.state != ^:error and b.state != ^:canceled
    )
  end

  @spec all(:awaiting_review) :: Ecto.Queryable.t()
  def all(:awaiting_review) do
    all = all_links_not_err()

    from(p in Patch,
      left_join: l in subquery(all),
      on: l.patch_id == p.id,
      where: is_nil(l.batch_id),
      where: p.open,
      order_by: [desc: p.pr_xref]
    )
  end

  @spec all_for_project(Project.id(), :open | :awaiting_review) :: Ecto.Queryable.t()
  def all_for_project(project_id, :open) do
    from(p in Patch,
      where: p.open,
      where: p.project_id == ^project_id,
      order_by: [desc: p.pr_xref]
    )
  end

  def all_for_project(project_id, :awaiting_review) do
    from(p in Patch.all(:awaiting_review),
      where: p.project_id == ^project_id,
      order_by: [desc: p.pr_xref]
    )
  end

  @spec dups_in_batches() :: Ecto.Queryable.t()
  def dups_in_batches do
    all = all_links_not_err()

    from(p in Patch,
      left_join: l in subquery(all),
      on: l.patch_id == p.id,
      where: p.open,
      group_by: p.id,
      having: count(p.id) > 1
    )
  end

  @spec ci_skip?(t) :: boolean()
  def ci_skip?(patch) do
    rexp = ~r/\[ci skip\]\[skip ci\]\[skip netlify\]/
    title = patch.title || ""
    body = patch.body || ""
    String.match?(title, rexp) or String.match?(body, rexp)
  end
end
