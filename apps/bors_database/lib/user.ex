defmodule BorsNG.Database.User do
  @moduledoc """
  A user account;
  each user account in our system has a corresponding GitHub account.
  """

  use BorsNG.Database.Model

  @type t :: %User{}

  schema "users" do
    field :user_xref, :integer
    field :login, :string
    field :is_admin, :boolean, default: false
    many_to_many :projects, Project, join_through: LinkUserProject

    timestamps()
  end

  def by_project(project_id) do
    from u in User,
      join: l in LinkUserProject,
      where: l.project_id == ^project_id,
      where: u.id == l.user_id
  end

  def has_perm(_repo, %User{is_admin: true}, _project_id) do
    true
  end

  def has_perm(repo, %User{id: id}, project_id) do
    params = [project_id: project_id, user_id: id]
    not is_nil repo.get_by(LinkUserProject, params)
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:user_xref, :login, :is_admin])
    |> unique_constraint(:user_xref, name: :users_user_xref_index)
  end
end
