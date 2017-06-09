defmodule BorsNG.Worker.BatcherMessageTest do
  use ExUnit.Case, async: true

  alias BorsNG.Worker.Batcher.Message

  test "generate configuration problem message" do
    expected_message = "# Configuration problem\nExample problem"
    actual_message = Message.generate_message({:config, "Example problem"})
    assert expected_message == actual_message
  end

  test "generate retry message" do
    expected_message = "# Build failed (retrying...)\n  * stat"
    example_statuses = [%{url: nil, identifier: "stat"}]
    actual_message = Message.generate_message({:retrying, example_statuses})
    assert expected_message == actual_message
  end

  test "generate retry message w/ url" do
    expected_message = "# Build failed (retrying...)\n  * [stat](x)"
    example_statuses = [%{url: nil, identifier: "stat", url: "x"}]
    actual_message = Message.generate_message({:retrying, example_statuses})
    assert expected_message == actual_message
  end

  test "generate failure message" do
    expected_message = "# Build failed\n  * stat"
    example_statuses = [%{url: nil, identifier: "stat"}]
    actual_message = Message.generate_message({:failed, example_statuses})
    assert expected_message == actual_message
  end

  test "generate success message" do
    expected_message = "# Build succeeded\n  * stat"
    example_statuses = [%{url: nil, identifier: "stat"}]
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
    expected_message = "Merge #1 #2\n\n1: Alpha r=r\n\na\n\n2: Beta r=s\n\nb\n"
    patches = [
      %{patch: %{pr_xref: 1, title: "Alpha", body: "a"}, reviewer: "r"},
      %{patch: %{pr_xref: 2, title: "Beta", body: "b"}, reviewer: "s"}]
    patches2 = [
      %{patch: %{pr_xref: 2, title: "Beta", body: "b"}, reviewer: "s"},
      %{patch: %{pr_xref: 1, title: "Alpha", body: "a"}, reviewer: "r"}]
    actual_message = Message.generate_commit_message(patches, nil)
    assert expected_message == actual_message
    actual_message2 = Message.generate_commit_message(patches2, nil)
    assert expected_message == actual_message2
  end

  test "cut body" do
    assert "a" == Message.cut_body("abc", "b")
  end

  test "cut body with multiple matches" do
    assert "aa" == Message.cut_body("aabcbd", "b")
  end

  test "cut body with no match" do
    assert "ac" == Message.cut_body("ac", "b")
  end

  test "cut commit message bodies" do
    expected_message = """
    Merge #1

    1: Synchronize background and foreground processing r=bill

    Fixes that annoying bug.
    """
    title = "Synchronize background and foreground processing"
    body = """
    Fixes that annoying bug.
    
    <!-- boilerplate follows -->
    
    Thank you for contributing to my awesome OSS project!
    To make sure your PR is accepted ASAP, make sure all of this
    stuff is done:
    
    - [ ] Run the linter
    - [ ] Run any new or changed tests
    - [ ] This PR fixes #___ (fill in if it exists)
    - [ ] Make sure your commit messages make sense
    """
    patches = [
      %{patch: %{pr_xref: 1, title: title, body: body}, reviewer: "bill"} ]
    actual_message = Message.generate_commit_message(
      patches,
      "\n\n<!-- boilerplate follows -->")
    assert expected_message == actual_message
  end
end
