defmodule BorsNG.GitHub.Merge do
  @moduledoc """
  The structure of GitHub squash result.
  """

  defstruct sha: ""

  @type tjson :: map

  @type t :: %BorsNG.GitHub.Merge{
               sha: bitstring
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
  }) do
    {:ok, %BorsNG.GitHub.Commit{
      sha: sha,
    }}
  end

  def from_json(x) do
    {:error, x}
  end
end
