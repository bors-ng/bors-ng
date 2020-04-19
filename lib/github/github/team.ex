defmodule BorsNG.GitHub.Team do
  @moduledoc """
  The GitHub structure of a team account.
  """

  @type tjson :: map

  @type t :: %BorsNG.GitHub.Team{
          id: integer,
          name: String.t()
        }

  defstruct(
    id: 0,
    name: ""
  )

  @doc """
  Convert from Poison-decoded JSON to a User struct.
  """
  @spec from_json!(tjson) :: t
  def from_json!(json) do
    {:ok, pr} = from_json(json)
    pr
  end

  @doc """
  Convert from Poison-decoded JSON to a User struct.
  """
  @spec from_json(tjson) :: {:ok, t} | :err
  def from_json(%{
        "id" => id,
        "name" => name
      })
      when is_integer(id) do
    {:ok,
     %BorsNG.GitHub.Team{
       id: id,
       name: name
     }}
  end

  def from_json(_) do
    :error
  end
end
