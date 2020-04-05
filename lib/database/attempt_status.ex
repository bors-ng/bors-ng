defmodule BorsNG.Database.AttemptStatus do
  @moduledoc """
  A database record for an individual CI run.
  It corresponds to an item in the status = []
  array of bors.toml.

  This version links to an attempt,
  rather than a batch.
  """

  use BorsNG.Database.Model
  alias BorsNG.Database.AttemptStatusState

  @type t :: %__MODULE__{}

  schema "attempt_statuses" do
    belongs_to(:attempt, Attempt)
    field(:identifier, :string)
    field(:url, :string)
    field(:state, AttemptStatusState)
    timestamps()
  end

  @spec changeset(t | Ecto.Changeset.t(), map) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:attempt_id, :identifier, :url, :state])
  end

  @spec get_for_attempt(Attempt.id(), String.t()) :: Ecto.Queryable.t()
  def get_for_attempt(attempt_id, identifier) do
    from(s in AttemptStatus,
      where: s.attempt_id == ^attempt_id,
      where: fragment("? LIKE ?", ^identifier, s.identifier)
    )
  end

  @spec all_for_attempt(Attempt.id()) :: Ecto.Queryable.t()
  def all_for_attempt(attempt_id) do
    from(s in AttemptStatus, where: s.attempt_id == ^attempt_id)
  end

  @spec all_for_attempt(Attempt.id(), AttemptStatusState.t() | :incomplete) :: Ecto.Queryable.t()
  def all_for_attempt(attempt_id, :incomplete) do
    from(s in AttemptStatus,
      where: s.attempt_id == ^attempt_id,
      where: s.state == 1 or s.state == 0
    )
  end

  def all_for_attempt(attempt_id, state) do
    from(s in AttemptStatus,
      where: s.attempt_id == ^attempt_id,
      where: s.state == ^state
    )
  end
end
