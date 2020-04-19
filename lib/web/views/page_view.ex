defmodule BorsNG.PageView do
  @moduledoc """
  The dashboard and greeting page.
  """

  use BorsNG.Web, :view

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
