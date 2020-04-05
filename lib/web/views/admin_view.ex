defmodule BorsNG.AdminView do
  @moduledoc """
  The view portion of all administrator-specific functions,
  such as looking up an arbitrary project by name,
  or showing the results of red-flag queries.
  """

  use BorsNG.Web, :view

  def truncate_commit(<<t::binary-size(7), _::binary>>), do: t
  def truncate_commit(t) when is_binary(t), do: t
  def truncate_commit(nil), do: "[nil]"
  def truncate_commit(_), do: "[invalid]"

  def htmlify_naive_datetime(datetime) do
    ["<time class=time-convert>", NaiveDateTime.to_iso8601(datetime), "+00:00</time>"]
    |> Phoenix.HTML.raw()
  end
end
