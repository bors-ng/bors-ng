defmodule BorsNG.GitHub.Commit do
  @moduledoc """
  The structure of GitHub commit data.
  """

  defstruct sha: "", author_name: "", author_email: ""

  @type tjson :: map

  @type t :: %BorsNG.GitHub.Commit{
    sha: bitstring,
    author_name: bitstring,
    author_email: bitstring,
  }

  @doc """
  Convert from Poison-decoded JSON to a Commit struct.
  """
  @spec from_json!(tjson) :: t
  def from_json!(json) do
    {:ok, pr} = from_json(json)
    pr
  end

  @doc """
  Convert from Poison-decoded JSON to a Commit struct.
  """
  @spec from_json(tjson) :: {:ok, t} | :err
  def from_json(%{
    "sha" => sha,
    "commit" => %{
      "author" => %{
        "name" => author_name,
        "email" => author_email,
      },
    },
  }) do
    {:ok, %BorsNG.GitHub.Commit{
      sha: sha,
      author_name: author_name,
      author_email: author_email,
    }}
  end

  def from_json(x) do
    {:error, x}
  end
end
