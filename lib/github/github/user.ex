defmodule BorsNG.GitHub.User do
  @moduledoc """
  The GitHub structure of a user account.  This is different from FullUser since this has many fewer fields.
  """

  defstruct id: 0, login: "", avatar_url: ""

  @type tjson :: map

  @type t :: %BorsNG.GitHub.User{
          id: integer,
          login: bitstring,
          avatar_url: bitstring
        }

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
        "login" => login,
        "avatar_url" => avatar_url
      })
      when is_integer(id) do
    {:ok,
     %BorsNG.GitHub.User{
       id: id,
       login: login,
       avatar_url: avatar_url
     }}
  end

  def from_json(_) do
    :error
  end
end
