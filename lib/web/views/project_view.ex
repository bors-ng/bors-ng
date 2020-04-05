defmodule BorsNG.ProjectView do
  @moduledoc """
  The list of repository's, and each individual repository page.

  n.b.
  We call it a project internally, though it corresponds
  to a GitHub repository. This is to avoid confusing
  a GitHub repo with an Ecto repo.
  """

  use BorsNG.Web, :view

  def stringify_state(state) do
    case state do
      :waiting -> "Waiting to run"
      :running -> "Running"
      :ok -> "Succeeded"
      :error -> "Failed"
      :canceled -> "Canceled"
      _ -> "Invalid"
    end
  end

  def truncate_commit(<<t::binary-size(7), _::binary>>), do: t
  def truncate_commit(t) when is_binary(t), do: t
  def truncate_commit(nil), do: "[nil]"
  def truncate_commit(_), do: "[invalid]"

  def htmlify_naive_datetime(datetime) do
    ["<td><time class=time-convert>", NaiveDateTime.to_iso8601(datetime), "+00:00</time></td>"]
    |> Phoenix.HTML.raw()
  end

  @doc """
  Checks to see if there is an empty list then returns true
  """
  def empty?([]), do: true

  @doc """
  Checks to see if the variable is a list with elements then returns false. 
  """
  def empty?(list) when is_list(list) do
    false
  end
end
