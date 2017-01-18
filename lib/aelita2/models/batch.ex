defmodule Aelita2.Batch do
  @moduledoc """
  The database-level representation of a "batch".

  A batch is a collection of patches that are running, or will run.
  """

  use Aelita2.Web, :model

  alias Aelita2.Batch

  schema "batches" do
    belongs_to :project, Aelita2.Project
    field :commit, :string
    field :state, :integer
    field :last_polled, :integer
    field :timeout_at, :integer
    timestamps()
  end

  def new(project_id) do
    %Batch{
      project_id: project_id,
      commit: nil,
      state: 0,
      last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)
    }
  end

  def atomize_state(state) do
    case state do
      0 -> :waiting
      1 -> :running
      2 -> :ok
      3 -> :err
    end
  end

  def numberize_state(st) do
    case st do
      :waiting -> 0
      :running -> 1
      :ok -> 2
      :err -> 3
    end
  end

  def all_for_project(project_id, :incomplete) do
    from b in Batch,
      where: b.project_id == ^project_id,
      where: (b.state == 0 or b.state == 1)
  end

  def all_for_project(project_id, :complete) do
    from b in Batch,
      where: b.project_id == ^project_id,
      where: (b.state == 2 or b.state == 3)
  end

  def all_assoc(:incomplete) do
    from b in Batch,
      join: p in assoc(b, :project),
      preload: [project: p],
      where: (b.state == 0 or b.state == 1)
  end

  def get_assoc_by_commit(commit) do
    from b in Batch,
      join: p in assoc(b, :project),
      preload: [project: p],
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
    period = if Batch.atomize_state(batch.state) == :waiting do
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
    |> cast(params, [:project_id, :commit, :state, :last_polled, :timeout_at])
  end
end
