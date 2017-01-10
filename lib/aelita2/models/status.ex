defmodule Aelita2.Status do
  @moduledoc """
  A database record for an individual CI run.
  It corresponds to an item in the status = []
  array of bors.toml.
  """

  use Aelita2.Web, :model

  alias Aelita2.Status

  schema "statuses" do
    belongs_to :batch, Aelita2.Batch
    field :identifier, :string
    field :url, :string
    field :state, :integer
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:batch_id, :identifier, :url, :state])
  end

  def get_for_batch(batch_id, identifier) do
    from s in Status,
      where: s.batch_id == ^batch_id,
      where: s.identifier == ^identifier
  end

  def all_for_batch(batch_id) do
    from s in Status, where: s.batch_id == ^batch_id
  end

  def all_for_batch(batch_id, :incomplete) do
    from s in Status,
      where: s.batch_id == ^batch_id,
      where: s.state == 1 or s.state == 0
  end

  def all_for_batch(batch_id, state) do
    state = Status.numberize_state(state)
    from s in Status,
      where: s.batch_id == ^batch_id,
      where: s.state == ^state
  end

  def atomize_state(state) do
    case state do
      0 -> :waiting
      1 -> :running
      2 -> :ok
      3 -> :err
    end
  end

  def numberize_state(state) do
    case state do
      :waiting -> 0
      :running -> 1
      :ok -> 2
      :err -> 3
    end
  end
end
