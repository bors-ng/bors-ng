defmodule Aelita2.Status do
  use Aelita2.Web, :model

  alias Aelita2.Status

  schema "statuses" do
    belongs_to :project, Aelita2.Project
    field :identifier, :string
    field :url, :string
    field :state, :integer
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:project_id, :identifier, :url, :state])
    |> validate_required([:project_id, :identifier, :url, :state])
  end

  def get_for_project(project_id, identifier) do
    from s in Status, where: s.project_id == ^project_id, where: s.identifier == ^identifier
  end

  def all_for_project(project_id) do
    from s in Status, where: s.project_id == ^project_id
  end

  def all_for_project(project_id, :incomplete) do
    from s in Status, where: s.project_id == ^project_id, where: s.state == 1 or s.state == 0
  end

  def all_for_project(project_id, state) do
    state = Status.state_numberize(state)
    from s in Status, where: s.project_id == ^project_id, where: s.state == ^state
  end

  def state_atomize(state) do
    case state do
      0 -> :waiting
      1 -> :running
      2 -> :ok
      3 -> :err
    end
  end

  def state_numberize(state) do
    case state do
      :waiting -> 0
      :running -> 1
      :ok -> 2
      :err -> 3
    end
  end
end
