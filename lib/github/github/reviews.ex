defmodule BorsNG.GitHub.Reviews do
  @moduledoc """
  The GitHub repository structure.
  """

  @type state :: binary
  @type t :: %{state => integer}

  @spec from_json!([map]) :: t
  def from_json!(json) do
    json
    # Count only the latest review from a user,
    # by deduplicating using the user id
    |> Enum.reduce(%{}, fn
      %{"state" => "COMMENTED"}, acc ->
        acc
      %{"user" => %{"id" => uid}, "state" => state}, acc ->
        Map.update(acc, uid, state, fn _ -> state end)
      end)
    # Remove reviews that don't count
    |> Enum.flat_map(fn {_uid, state} ->
        case state do
          # Ignore dismissed reviews
          "DISMISSED" -> []
          # Pass just the stage on to the next pipeline item
          state -> [state]
        end
      end)
    # Reduce the list of states in to a count per state, with
    # defaults in place for the two states we're going to look at
    |> Enum.reduce(%{"APPROVED" => 0, "CHANGES_REQUESTED" => 0},
      fn state, acc ->
        Map.update(acc, state, 1, fn x -> x + 1 end)
      end)
  end
end
