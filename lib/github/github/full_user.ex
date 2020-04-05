defmodule BorsNG.GitHub.FullUser do
  @moduledoc """
  The GitHub structure of a detailed user account.

  See https://developer.github.com/v3/users/#get-a-single-user
  """

  defstruct id: 0, login: "", avatar_url: "", email: "", name: nil

  @type tjson :: map

  @type t :: %BorsNG.GitHub.FullUser{
          id: integer,
          login: bitstring,
          avatar_url: bitstring,
          email: bitstring,
          name: bitstring
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
        "email" => email,
        "name" => name
      })
      when is_integer(id) do
    {:ok,
     %BorsNG.GitHub.FullUser{
       id: id,
       login: login,
       avatar_url: avatar_url,
       email: email,
       name: name
     }}
  end

  def from_json(_) do
    :error
  end
end
