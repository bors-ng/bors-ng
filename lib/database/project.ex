defmodule BorsNG.Database.Project do
  @moduledoc """
  Corresponds to a repo in GitHub, as opposed to a repo in Ecto.

  This also corresponds to a queue of batches.
  """

  use BorsNG.Database.Model
  alias BorsNG.Database.ProjectPermission

  @type t :: %Project{}

  @doc """
  After modifying the underlying model,
  call this to notify the UI.
  """
  def ping!(project_id) when not is_binary(project_id) do
    ping!(to_string(project_id))
  end
  def ping!(project_id) do
    BorsNG.Endpoint.broadcast!("project_ping:#{project_id}", "new_msg", %{})
  end

  schema "projects" do
    belongs_to :installation, Installation
    field :repo_xref, :integer
    field :name, :string
    many_to_many :users, User, join_through: LinkUserProject,
                 on_replace: :delete
    many_to_many :members, User, join_through: LinkMemberProject,
                 on_replace: :delete
    field :staging_branch, :string, default: "staging"
    field :trying_branch, :string, default: "trying"
    field :batch_poll_period_sec, :integer, default: (60 * 30)
    field :batch_delay_sec, :integer, default: 10
    field :batch_timeout_sec, :integer, default: (60 * 60 * 2)
    field :auto_reviewer_required_perm, ProjectPermission, default: nil
    field :auto_member_required_perm, ProjectPermission, default: nil

    timestamps()
  end

  def installation_project_connection(project_id, repo) do
    {installation_xref, repo_xref} = from(p in Project,
      join: i in Installation, on: i.id == p.installation_id,
      where: p.id == ^project_id,
      select: {i.installation_xref, p.repo_xref})
    |> repo.one!()
    {{:installation, installation_xref}, repo_xref}
  end

  def installation_connection(repo_xref, repo) do
    {installation_xref, repo_xref} = from(p in Project,
      join: i in Installation, on: i.id == p.installation_id,
      where: p.repo_xref == ^repo_xref,
      select: {i.installation_xref, p.repo_xref})
    |> repo.one!()
    {{:installation, installation_xref}, repo_xref}
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:repo_xref, :name, :auto_reviewer_required_perm,
                     :auto_member_required_perm])
  end
  def changeset_branches(struct, params \\ %{}) do
    struct
    |> cast(params, [:staging_branch, :trying_branch])
    |> validate_required([:staging_branch, :trying_branch])
  end
  def changeset_reviewer_settings(struct, params \\ %{}) do
    struct
    |> cast(params, [:auto_reviewer_required_perm])
  end
  def changeset_member_settings(struct, params \\ %{}) do
    struct
    |> cast(params, [:auto_member_required_perm])
  end

  # Red flag queries
  # These should always return [].

  def orphans do
    from p in Project,
      left_join: l in LinkUserProject, on: p.id == l.project_id,
      where: is_nil l.user_id
  end
end
