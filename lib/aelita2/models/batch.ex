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
      join: i in assoc(p, :installation),
      preload: [project: {p, installation: i}],
      where: (b.state == 0 or b.state == 1)
  end

  def get_assoc_by_commit(commit) do
    from b in Batch,
      join: p in assoc(b, :project),
      join: i in assoc(p, :installation),
      preload: [project: {p, installation: i}],
      where: b.commit == ^commit
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:project_id, :commit, :state, :last_polled])
  end
end
