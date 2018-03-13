defmodule BorsNG.GitHub.Reviews do
  @moduledoc """
  The GitHub repository structure.
  """

  @type t :: %{
    "APPROVED": integer,
    "CHANGES_REQUESTED": integer
  }

  @spec from_json!(term) :: t
  def from_json!(json) do
    json
    |> Enum.reduce(%{},
      fn (%{"user" => %{"id" => uid}} = key, acc) ->
        Map.update(acc, uid, key, fn _ -> key end)
      end)
    |> Enum.map(fn {_uid, %{
        "author_association" => association,
        "state" => state
      }} -> {association, state} end)
    # Filter out reviews where the reviewer is not connected to the project
    |> Enum.filter(fn {association, _} -> association != "NONE" end)
    # Filter out dismissed reviews
    |> Enum.filter(fn {_, state} -> state != "DISMISSED" end)
    |> Enum.map(fn {_, state} -> state end)
    # Reduce the list of states in to a count per state, with
    # defaults in place for the two states we're going to look at
    |> Enum.reduce(%{"APPROVED" => 0, "CHANGES_REQUESTED" => 0},
      fn (key, acc) ->
        Map.update(acc, key, 0, fn x -> x + 1 end)
      end)
  end
end
