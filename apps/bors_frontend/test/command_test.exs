defmodule BorsNG.CommandTest do
  use ExUnit.Case, async: true

  alias BorsNG.Command

  doctest BorsNG.Command

  test "reject the empty string" do
    assert :nomatch == Command.parse("")
    assert :nomatch == Command.parse(nil)
  end

  test "reject strings without the phrase" do
    assert :nomatch == Command.parse("doink!")
  end

  test "reject a string that merely starts out like a command" do
    assert :nomatch == Command.parse("bors doink")
  end

  test "accept the bare command" do
    assert {:try, ""} == Command.parse("bors try")
    assert :activate == Command.parse("bors r+")
    assert :deactivate == Command.parse("bors r-")
  end

  test "accept the try command with an argument" do
    assert {:try, "-layout"} == Command.parse("bors try-layout")
  end

  test "accept the try command with more argumentation" do
    assert {:try, " --layout --script"} ==
      Command.parse("bors try --layout --script")
  end

  test "accept the command with a prefix" do
    assert {:try, "Z"} == Command.parse("Xbors tryZ")
  end
end
