defmodule BorsNG.GitHub.File do
  @moduledoc """
  The structure of GitHub pull request file
  """

  @type t :: %BorsNG.GitHub.File{
          filename: String.t()
        }
  defstruct(filename: "")

  @doc """
  Convert from JSON string to a File struct.
  """
  @spec from_json!(map) :: t
  def from_json!(json) do
    {:ok, files} = from_json(json)
    files
  end

  @doc """
  Convert from JSON string to a File struct.
  """
  @spec from_json(map) :: {:ok, t} | {:error, map}
  def from_json(%{"filename" => filename}) do
    {:ok, %BorsNG.GitHub.File{filename: filename}}
  end

  def from_json(x) do
    {:error, x}
  end
end
