defmodule BorsNG.Database.Attempt do
  @moduledoc """
  The database-level representation of a "attempt".

  When a patch is tried, it gets merged with master individually
  and it's CI result is reported, but it is not pushed to master.
  """

  use BorsNG.Database.Model
  alias BorsNG.Database.AttemptState

  @type t :: %__MODULE__{}
  @type id :: pos_integer

  schema "attempts" do
    belongs_to(:patch, Patch)
    field(:into_branch, :string)
    field(:commit, :string)
    field(:state, AttemptState)
    field(:last_polled, :integer)
    field(:timeout_at, :integer)
    field(:arguments, :string)
    timestamps()
  end

  @spec new(Patch.t(), String.t()) :: t
  def new(%Patch{} = patch, arguments) do
    %Attempt{
      patch_id: patch.id,
      patch: patch,
      into_branch: patch.into_branch,
      commit: nil,
      state: 0,
      arguments: arguments,
      last_polled: DateTime.to_unix(DateTime.utc_now(), :second)
    }
  end

  @spec all(AttemptState.t() | :incomplete) :: Ecto.Queryable.t()
  def all(:incomplete) do
    from(b in Attempt,
      where: b.state == 0 or b.state == 1
    )
  end

  def all(state) do
    from(b in Attempt,
      where: b.state == ^state
    )
  end

  @spec all_for_project(Project.id(), AttemptState.t() | :incomplete) :: Ecto.Queryable.t()
  def all_for_project(project_id, state) do
    from(b in all(state),
      join: p in Patch,
      on: p.id == b.patch_id,
      where: p.project_id == ^project_id
    )
  end

  @spec all_for_patch(Patch.id()) :: Ecto.Queryable.t()
  def all_for_patch(patch_id) do
    from(b in Attempt,
      where: b.patch_id == ^patch_id
    )
  end

  @spec all_for_patch(Patch.id(), AttemptState.t() | :complete | :incomplete | nil) ::
          Ecto.Queryable.t()
  def all_for_patch(patch_id, nil), do: all_for_patch(patch_id)

  def all_for_patch(patch_id, :incomplete) do
    from(b in all_for_patch(patch_id),
      where: b.state == 0 or b.state == 1
    )
  end

  def all_for_patch(patch_id, :complete) do
    from(b in all_for_patch(patch_id),
      where: b.state == 2 or b.state == 3 or b.state == 4
    )
  end

  def all_for_patch(patch_id, state) do
    from(b in all_for_patch(patch_id),
      where: b.state == ^state
    )
  end

  @spec get_by_commit(Project.id(), String.t(), AttemptState.t() | :incomplete) ::
          Ecto.Queryable.t()
  def get_by_commit(project_id, commit, state) do
    from(b in all(state),
      join: p in Patch,
      on: p.id == b.patch_id,
      where: b.commit == ^commit and p.project_id == ^project_id
    )
  end

  @spec next_poll_is_past(t, Project.t()) :: boolean
  def next_poll_is_past(attempt, project) do
    now = DateTime.to_unix(DateTime.utc_now(), :second)
    next_poll_is_past(attempt, project, now)
  end

  @spec next_poll_is_past(t, Project.t(), pos_integer) :: boolean
  def next_poll_is_past(attempt, project, now_utc_sec) do
    next = get_next_poll_unix_sec(attempt, project)
    next < now_utc_sec
  end

  @spec timeout_is_past(t) :: boolean
  def timeout_is_past(%Attempt{timeout_at: timeout_at}) do
    now = DateTime.to_unix(DateTime.utc_now(), :second)
    now > timeout_at
  end

  @spec get_next_poll_unix_sec(t, Project.t()) :: non_neg_integer
  def get_next_poll_unix_sec(attempt, project) do
    attempt.last_polled + project.batch_poll_period_sec
  end

  @spec changeset(t | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch_id, :commit, :state, :last_polled, :timeout_at])
  end

  @spec changeset_state(t | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset_state(struct, params \\ %{}) do
    struct
    |> cast(params, [:state])
  end
end
