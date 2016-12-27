defmodule Aelita2.Batch do
  use Aelita2.Web, :model

  alias Aelita2.Batch

  schema "batches" do
    belongs_to :project, Aelita2.Project
    field :commit, :string
    field :state, :integer
    field :last_polled, :integer
    timestamps()
  end

  def atomize_state(state) do
    case state do
      0 -> :waiting
      1 -> :running
    end
  end

  def numberize_state(st) do
    case st do
      :waiting -> 0
      :running -> 1
    end
  end

  def all_for_project(project_id) do
    from(b in Batch, where: b.project_id == ^project_id)
  end

  def all_assoc() do
    from b in Batch,
      join: p in assoc(b, :project),
      join: i in assoc(p, :installation),
      preload: [project: {p, installation: i}]
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:project_id, :commit, :state, :last_polled])
    |> validate_required([:project_id, :commit, :state, :last_polled])
  end
end
