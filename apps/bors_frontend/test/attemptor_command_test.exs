defmodule BorsNG.AttemptorCommandTest do
  use ExUnit.Case, async: true

  alias BorsNG.Attemptor.Command

  test "reject the empty string" do
    assert :nomatch == Command.parse("")
  end

  test "reject strings without the phrase" do
    assert :nomatch == Command.parse("doink!")
  end

  test "reject a string that merely starts out like a command" do
    assert :nomatch == Command.parse("bors doink")
  end

  test "accept the bare command" do
    assert "" == Command.parse("bors try")
  end

  test "accept the command with an argument" do
    assert "-layout" == Command.parse("bors try-layout")
  end

  test "accept the command with more argumentation" do
    assert " --layout --script" == Command.parse("bors try --layout --script")
  end

  test "accept the command with a prefix" do
    assert "Z" == Command.parse("Xbors tryZ")
  end
end
