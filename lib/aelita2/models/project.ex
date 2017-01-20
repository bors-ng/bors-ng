defmodule Aelita2.Project do
  @moduledoc """
  Corresponds to a repo in GitHub, as opposed to a repo in Ecto.

  This also corresponds to a queue of batches.
  """

  use Aelita2.Web, :model

  alias Aelita2.Installation
  alias Aelita2.LinkUserProject
  alias Aelita2.Project
  alias Aelita2.User

  schema "projects" do
    belongs_to :installation, Installation
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
    from p in Project,
      join: l in LinkUserProject, on: p.id == l.project_id,
      where: l.user_id == ^owner_id
  end

  def ping!(project_id) do
    Aelita2.Endpoint.broadcast! "project_ping:#{project_id}", "new_msg", %{}
  end

  def installation_connection(repo_xref) do
    from p in Project,
      join: i in Installation, on: i.id == p.installation_id,
      where: p.repo_xref == ^repo_xref,
      select: %{
        repo: p.repo_xref,
        installation: i.installation_xref,
      }
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:repo_xref, :name])
  end
  def changeset_branches(struct, params \\ %{}) do
    struct
    |> cast(params, [:master_branch, :staging_branch])
    |> validate_required([:master_branch, :staging_branch])
  end

  # Red flag queries
  # These should always return [].

  def orphans do
    from p in Project,
      left_join: l in LinkUserProject, on: p.id == l.project_id,
      where: is_nil l.user_id
  end
end
