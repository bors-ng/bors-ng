defmodule BorsNG.CommandTest do
  use ExUnit.Case, async: true

  alias BorsNG.Command

  doctest BorsNG.Command

  test "reject the empty string" do
    assert [] == Command.parse("")
    assert [] == Command.parse(nil)
  end

  test "reject strings without the phrase" do
    assert [] == Command.parse("doink!")
  end

  test "reject a string that merely starts out like a command" do
    assert [] == Command.parse("bors doink")
  end

  test "accept the bare command" do
    assert [{:try, ""}] == Command.parse("bors try")
    assert [:activate] == Command.parse("bors r+")
    assert [:deactivate] == Command.parse("bors r-")
  end

  test "accept the try command with an argument" do
    assert [{:try, "-layout"}] == Command.parse("bors try-layout")
  end

  test "accept more than one command in a single comment" do
    expected = [
      {:try, ""},
      :deactivate]
    command = """
    bors try
    bors r-
    """
    assert expected == Command.parse(command)
  end

  test "accept the try command with more argumentation" do
    assert [{:try, " --layout --script"}] ==
      Command.parse("bors try --layout --script")
  end

  test "do not accept the command with a prefix" do
    assert [] == Command.parse("Xbors tryZ")
  end
end
