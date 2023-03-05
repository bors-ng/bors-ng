defmodule BorsNG.Database.Hook do
  @moduledoc """
  A database record for an individual hook call.

  See https://bors.tech/rfcs/0322-pre-test-and-pre-merge-hooks.html
  """

  @type t :: %__MODULE__{}
  @type state_n :: 0 | 1 | 2 | 3
  @type state :: :queued | :pending | :ok | :error

  use BorsNG.Database.Model
  alias BorsNG.Database.HookState

  schema "hooks" do
    belongs_to(:batch, Batch)
    field(:identifier, :string)
    field(:index, :integer)
    field(:url, :string)
    field(:state, HookState)
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:batch_id, :identifier, :index, :url, :state])
  end

  def get_next(batch_id, index) do
    from(s in Hook,
      where: s.batch_id == ^batch_id,
      where: s.index == ^index + 1)
  end

  def get_for_identifier(identifier) do
    from(s in Hook, where: s.identifier == ^identifier)
  end

  def all_for_batch(batch_id) do
    from(s in Hook, where: s.batch_id == ^batch_id)
  end

  def all_for_batch(batch_id, :incomplete) do
    from(s in Hook,
      where: s.batch_id == ^batch_id,
      where: s.state == 1 or s.state == 0
    )
  end

  def all_for_batch(batch_id, state) do
    from(s in Hook,
      where: s.batch_id == ^batch_id,
      where: s.state == ^state
    )
  end
end
