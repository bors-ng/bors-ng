defmodule BorsNG.PageView do
  @moduledoc """
  The dashboard and greeting page.
  """

  use BorsNG.Web, :view

  @doc """
  Checks to see if there is an empty list then returns true,
  or if the variable is a list with elements then returns false. 
  """
  def empty?([]), do: true

  def empty?(list) when is_list(list) do
    false
  end
end
