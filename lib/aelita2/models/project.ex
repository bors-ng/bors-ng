defmodule Aelita2.Project do
  use Aelita2.Web, :model

  alias Aelita2.LinkUserProject
  alias Aelita2.User

  schema "projects" do
    belongs_to :installation, Aelita2.Installation
    field :repo_xref, :integer
    field :name, :string
    many_to_many :users, User, join_through: LinkUserProject
    field :master_branch, :string, default: "master"
    field :staging_branch, :string, default: "staging"
    field :batch_poll_period_sec, :integer, default: (60 * 30)
    field :batch_delay_sec, :integer, default: 10
    field :batch_timeout_sec, :integer, default: (60 * 60 * 2)

    timestamps()
  end

  def by_owner(owner_id) do
    Aelita2.Repo.all(from l in LinkUserProject,
      where: l.user_id == ^owner_id,
      preload: :project)
    |> Enum.map(&(&1.project))
  end

  def ping!(project_id) do
    Aelita2.Endpoint.broadcast! "project_ping:#{project_id}", "new_msg", %{}
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:repo_xref, :name])
  end
end
