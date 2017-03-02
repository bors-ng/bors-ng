defmodule Aelita2.Attemptor.Command do
  @moduledoc """
  The bors comment CLI allows parameters to be passed to try.
  Assuming the activation phrase is "bors try", you can do things like this:

      bors try --layout

  And the commit will come out like:

      Try #13: --layout

  Your build scripts should then inspect the commit message
  to pull out the commands.
  """

  @try_phrase Application.get_env(:aelita2, Aelita2)[:try_phrase]

  @spec parse(binary) :: binary | :nomatch
  def parse(@try_phrase <> arguments) do
    arguments
  end

  def parse(<<_, rest :: binary>>) do
    parse(rest)
  end

  def parse(<<>>) do
    :nomatch
  end
end
