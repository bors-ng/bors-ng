defmodule Aelita2.GitHub.Pr do
  @moduledoc """
  The structure of GitHub pull requests
  """

  @type tjson :: map
  @type t :: %Aelita2.GitHub.Pr{
    number: integer,
    title: bitstring | nil,
    body: bitstring | nil,
    state: :open | :closed,
    base_ref: bitstring,
    head_sha: bitstring,
    user: Aelita2.GitHub.User.t,
  }
  defstruct(
    number: 0,
    title: "",
    body: "",
    state: :closed,
    base_ref: "",
    head_sha: "",
    user: nil,
    )

  @doc """
  Convert from Poison-decoded JSON to a Pr struct.
  """
  @spec from_json!(tjson) :: t
  def from_json!(json) do
    {:ok, pr} = from_json(json)
    pr
  end

  @doc """
  Convert from Poison-decoded JSON to a Pr struct.
  """
  @spec from_json(tjson) :: {:ok, t} | :err
  def from_json(%{
    "number" => number,
    "title" => title,
    "body" => body,
    "state" => state,
    "base" => %{
      "ref" => base_ref,
    },
    "head" => %{
      "sha" => head_sha
    },
    "user" => %{
      "id" => user_id,
      "login" => user_login,
      "avatar_url" => user_avatar_url,
    },
  }) when is_integer(number) do
    {:ok, %Aelita2.GitHub.Pr{
      number: number,
      title: (case title do
        nil -> ""
        x -> x
      end),
      body: (case body do
        nil -> ""
        x -> x
      end),
      state: (case state do
        "open" -> :open
        "closed" -> :closed
      end),
      base_ref: base_ref,
      head_sha: head_sha,
      user: %Aelita2.GitHub.User{
        id: user_id,
        login: user_login,
        avatar_url: user_avatar_url,
      }
    }}
  end

  def from_json(_) do
    :error
  end
end
