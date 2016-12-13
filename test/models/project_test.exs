defmodule Aelita2.ProjectTest do
  use Aelita2.ModelCase

  alias Aelita2.Project

  @valid_attrs %{name: "some content", owner: "some content", repo_id: 42}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = Project.changeset(%Project{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = Project.changeset(%Project{}, @invalid_attrs)
    refute changeset.valid?
  end
end
