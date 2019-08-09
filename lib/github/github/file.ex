defmodule BorsNG.GitHub.File do
  @moduledoc """
  The structure of GitHub pull request file
  """

  @type tjson :: map
  @type t :: %BorsNG.GitHub.File{
          filename: bitstring
        }
  defstruct(filename: "")

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
  @spec from_json(tjson) :: {:ok, t} | {:error, term}
  def from_json([
        %{
          "filename" => f
        }
      ]) do
    {:ok,
     [
       %BorsNG.GitHub.File{
         filename: f
       }
     ]}
  end

  def from_json(x) do
    {:error, x}
  end
end
