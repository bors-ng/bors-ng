defmodule BorsNG.Database.Attempt do
  @moduledoc """
  The database-level representation of a "attempt".

  When a patch is tried, it gets merged with master individually
  and it's CI result is reported, but it is not pushed to master.
  """

  use BorsNG.Database.Model
  alias BorsNG.Database.AttemptState

  schema "attempts" do
    belongs_to :patch, Patch
    field :into_branch, :string
    field :commit, :string
    field :state, AttemptState
    field :last_polled, :integer
    field :timeout_at, :integer
    timestamps()
  end

  def new(%Patch{} = patch) do
    %Attempt{
      patch_id: patch.id,
      into_branch: patch.into_branch,
      commit: nil,
      state: 0,
      last_polled: DateTime.to_unix(DateTime.utc_now(), :seconds)
    }
  end

  def all(:incomplete) do
    from b in Attempt,
      where: b.state == 0 or b.state == 1
  end

  def all_for_project(project_id, state) do
    from b in all(state),
      join: p in Patch, on: p.id == b.patch_id,
      where: p.project_id == ^project_id
  end

  def all_for_patch(patch_id) do
    from b in Attempt,
      where: b.patch_id == ^patch_id
  end

  def all_for_patch(patch_id, nil), do: all_for_patch(patch_id)

  def all_for_patch(patch_id, :incomplete) do
    from b in all_for_patch(patch_id),
      where: b.state == 0 or b.state == 1
  end

  def all_for_patch(patch_id, :complete) do
    from b in all_for_patch(patch_id),
      where: b.state == 2 or b.state == 3 or b.state == 4
  end

  def all_for_patch(patch_id, state) do
    from b in all_for_patch(patch_id),
      where: b.state == ^state
  end

  def get_by_commit(commit, state) do
    from b in all(state),
      where: b.commit == ^commit
  end

  def next_poll_is_past(attempt, project) do
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    next_poll_is_past(attempt, project, now)
  end

  def next_poll_is_past(attempt, project, now_utc_sec) do
    next = get_next_poll_unix_sec(attempt, project)
    next < now_utc_sec
  end

  def timeout_is_past(%Attempt{timeout_at: timeout_at}) do
    now = DateTime.to_unix(DateTime.utc_now(), :seconds)
    now > timeout_at
  end

  def get_next_poll_unix_sec(attempt, project) do
    attempt.last_polled + project.batch_poll_period_sec
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch_id, :commit, :state, :last_polled, :timeout_at])
  end
end
