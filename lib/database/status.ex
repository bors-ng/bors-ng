defmodule BorsNG.Database.Status do
  @moduledoc """
  A database record for an individual CI run.
  It corresponds to an item in the status = []
  array of bors.toml.
  """

  @type t :: %__MODULE__{}
  @type state_n :: 0 | 1 | 2 | 3
  @type state :: :waiting | :running | :ok | :error

  use BorsNG.Database.Model
  alias BorsNG.Database.StatusState

  schema "statuses" do
    belongs_to(:batch, Batch)
    field(:identifier, :string)
    field(:url, :string)
    field(:state, StatusState)
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:batch_id, :identifier, :url, :state])
  end

  def get_for_batch(batch_id, identifier) do
    from(s in Status,
      where: s.batch_id == ^batch_id,
      where: fragment("? LIKE ?", ^identifier, s.identifier)
    )
  end

  def all_for_batch(batch_id) do
    from(s in Status, where: s.batch_id == ^batch_id)
  end

  def all_for_batch(batch_id, :incomplete) do
    from(s in Status,
      where: s.batch_id == ^batch_id,
      where: s.state == 1 or s.state == 0
    )
  end

  def all_for_batch(batch_id, state) do
    from(s in Status,
      where: s.batch_id == ^batch_id,
      where: s.state == ^state
    )
  end
end
