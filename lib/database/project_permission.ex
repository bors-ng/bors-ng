defmodule BorsNG.Database.ProjectPermission do
  @behaviour Ecto.Type
  @moduledoc """
  A type to represent the permissions of a project member.
  """

  def type, do: :string

  def select_list,
    do: [
      {"None", nil},
      {"Admin", :admin},
      {"Push", :push},
      {"Pull", :pull}
    ]

  def cast("") do
    {:ok, nil}
  end

  def cast(data) when data in ["nil", "admin", "push", "pull"] do
    {:ok, String.to_atom(data)}
  end

  def cast(data) when data in [nil, :admin, :push, :pull] do
    {:ok, data}
  end

  def cast(_), do: :error

  def load(data) do
    cast(data)
  end

  def dump(data) when data in [nil, :admin, :push, :pull] do
    {:ok, Atom.to_string(data)}
  end

  def dump(_), do: :error
end
