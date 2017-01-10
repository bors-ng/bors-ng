defmodule Aelita2.LinkUserProject do
  @moduledoc """
  The connection between a project and its reviewers.

  People with this link can bring up the dashboard page and settings
  for a project, and can r+ a commit. Otherwise, they can't.
  """

  use Aelita2.Web, :model

  schema "link_user_project" do
    belongs_to :user, Aelita2.User
    belongs_to :project, Aelita2.Project
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:user_id, :project_id])
    |> validate_required([:user_id, :project_id])
    |> unique_constraint(
      :user_id,
      name: :link_user_project_user_id_project_id_index)
  end
end
