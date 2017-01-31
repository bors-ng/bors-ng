defmodule Aelita2.GitHub.User do
  @moduledoc """
  The GitHub structure of a user account.
  """

  defstruct id: 0, login: "", avatar_url: ""

  @type tjson :: map

  @type t :: %Aelita2.GitHub.User{
    id: integer,
    login: bitstring,
    avatar_url: bitstring,
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
    "avatar_url" => avatar_url,
  }) when is_integer(id) do
    {:ok, %Aelita2.GitHub.User{
      id: id,
      login: login,
      avatar_url: avatar_url,
    }}
  end

  def from_json(_) do
    :error
  end
end
