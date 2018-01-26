defmodule BorsNG.Database.Batch do
  @moduledoc """
  The database-level representation of a "batch".

  A batch is a collection of patches that are running, or will run.
  """

  use BorsNG.Database.Model
  alias BorsNG.Database.BatchState

  schema "batches" do
    belongs_to :project, Project
    field :into_branch, :string
    field :commit, :string
    field :state, BatchState
    field :last_polled, :integer
    field :timeout_at, :integer
    field :priority, :integer, default: 0
    has_many :patches, LinkPatchBatch
    timestamps()
  end

  def new(project_id, into_branch, priority \\ 0) do
    %Batch{
      into_branch: into_branch,
      project_id: project_id,
      commit: nil,
      state: :waiting,
      last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds),
      priority: priority
    }
  end

  def is_empty(batch_id, repo) do
    links = LinkPatchBatch
    |> where([l], l.batch_id == ^batch_id)
    |> repo.all()
    links == []
  end

  def all_for_project(project_id) do
    from b in Batch,
      where: b.project_id == ^project_id
  end

  def all_for_project(project_id, nil), do: all_for_project(project_id)

  def all_for_project(project_id, :incomplete) do
    from b in all_for_project(project_id),
      where: b.state == ^(:waiting) or b.state == ^(:running)
  end

  def all_for_project(project_id, :complete) do
    from b in all_for_project(project_id),
      where: b.state == ^(:ok)
        or b.state == ^(:error)
        or b.state == ^(:canceled)
  end

  def all_for_project(project_id, state) do
    from b in all_for_project(project_id),
      where: b.state == ^state
  end

  def all_for_patch(patch_id, state \\ nil) do
    from b in all_assoc(state),
      join: l in LinkPatchBatch, on: l.batch_id == b.id,
      where: l.patch_id == ^patch_id
  end

  def all_assoc do
    from b in Batch,
      join: p in assoc(b, :project),
      preload: [project: p]
  end

  def all_assoc(nil), do: all_assoc()

  def all_assoc(:incomplete) do
    from b in all_assoc(),
      where: b.state == ^(:waiting) or b.state == ^(:running)
  end

  def all_assoc(:complete) do
    from b in all_assoc(),
      where: b.state == ^(:ok)
        or b.state == ^(:error)
        or b.state == ^(:canceled)
  end

  def get_assoc_by_commit(commit, state \\ nil) do
    from b in all_assoc(state),
      where: b.commit == ^commit
  end

  def next_poll_is_past(batch) do
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    next_poll_is_past(batch, now)
  end

  def next_poll_is_past(batch, now_utc_sec) do
    next = get_next_poll_unix_sec(batch)
    next < now_utc_sec
  end

  def timeout_is_past(%Batch{timeout_at: timeout_at}) do
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    now > timeout_at
  end

  def get_next_poll_unix_sec(batch) do
    period = if batch.state == :waiting do
      batch.project.batch_delay_sec
    else
      batch.project.batch_poll_period_sec
    end
    batch.last_polled + period
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [
      :project_id,
      :commit,
      :state,
      :last_polled,
      :timeout_at,
      :priority
    ])
  end
end
