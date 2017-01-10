defmodule Aelita2.BatcherMessageTest do
  use ExUnit.Case, async: true

  alias Aelita2.Batcher.Message
  alias Aelita2.Patch
  alias Aelita2.Status

  test "generate configuration problem message" do
    expected_message = "# Configuration problem\nExample problem"
    actual_message = Message.generate_message({:config, "Example problem"})
    assert expected_message == actual_message
  end

  test "generate retry message" do
    expected_message = "# Build failed (retrying...)\n  * stat"
    example_statuses = [%Status{identifier: "stat"}]
    actual_message = Message.generate_message({:retrying, example_statuses})
    assert expected_message == actual_message
  end

  test "generate retry message w/ url" do
    expected_message = "# Build failed (retrying...)\n  * [stat](x)"
    example_statuses = [%Status{identifier: "stat", url: "x"}]
    actual_message = Message.generate_message({:retrying, example_statuses})
    assert expected_message == actual_message
  end

  test "generate failure message" do
    expected_message = "# Build failed\n  * stat"
    example_statuses = [%Status{identifier: "stat"}]
    actual_message = Message.generate_message({:failed, example_statuses})
    assert expected_message == actual_message
  end

  test "generate success message" do
    expected_message = "# Build succeeded\n  * stat"
    example_statuses = [%Status{identifier: "stat"}]
    actual_message = Message.generate_message({:succeeded, example_statuses})
    assert expected_message == actual_message
  end

  test "generate conflict message" do
    expected_message = "# Merge conflict"
    actual_message = Message.generate_message({:conflict, :failed})
    assert expected_message == actual_message
  end

  test "generate conflict/retry message" do
    expected_message = "# Merge conflict (retrying...)"
    actual_message = Message.generate_message({:conflict, :retrying})
    assert expected_message == actual_message
  end

  test "generate commit message" do
    expected_message = "Merge #1 #2\n\n1: Alpha\n2: Beta\n"
    patches = [
      %Patch{pr_xref: 1, title: "Alpha"},
      %Patch{pr_xref: 2, title: "Beta"}]
    patches2 = [
      %Patch{pr_xref: 2, title: "Beta"},
      %Patch{pr_xref: 1, title: "Alpha"}]
    actual_message = Message.generate_commit_message(patches)
    assert expected_message == actual_message
    actual_message2 = Message.generate_commit_message(patches2)
    assert expected_message == actual_message2
  end
end
