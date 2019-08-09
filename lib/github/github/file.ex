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
  @spec from_json!(tjson) :: [t]
  def from_json!(json) do
    {:ok, files} = from_json(json)
    files
  end

  @doc """
  Convert from Poison-decoded JSON to a Pr struct.
  """
  @spec from_json(tjson) :: {:ok, [t]} | {:error}
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
