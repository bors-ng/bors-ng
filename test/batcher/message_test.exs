defmodule BorsNG.Worker.BatcherMessageTest do
  use ExUnit.Case, async: true

  alias BorsNG.Worker.Batcher.Message

  test "generate configuration problem message" do
    expected_message = "Configuration problem:\nExample problem"
    actual_message = Message.generate_message({:config, "Example problem"})
    assert expected_message == actual_message
  end

  test "generate retry message" do
    expected_message = "Build failed (retrying...):\n  * stat"
    example_statuses = [%{url: nil, identifier: "stat"}]
    actual_message = Message.generate_message({:retrying, example_statuses})
    assert expected_message == actual_message
  end

  test "generate retry message w/ url" do
    expected_message = "Build failed (retrying...):\n  * [stat](x)"
    example_statuses = [%{url: "x", identifier: "stat"}]
    actual_message = Message.generate_message({:retrying, example_statuses})
    assert expected_message == actual_message
  end

  test "generate failure message" do
    expected_message = "Build failed:\n  * stat"
    example_statuses = [%{url: nil, identifier: "stat"}]
    actual_message = Message.generate_message({:failed, example_statuses})
    assert expected_message == actual_message
  end

  test "generate success message" do
    expected_message = "Build succeeded:\n  * stat"
    example_statuses = [%{url: nil, identifier: "stat"}]
    actual_message = Message.generate_message({:succeeded, example_statuses})
    assert expected_message == actual_message
  end

  test "generate conflict message" do
    expected_message = "Merge conflict."
    actual_message = Message.generate_message({:conflict, :failed})
    assert expected_message == actual_message
  end

  test "generate canceled message" do
    expected_message = "Canceled."
    actual_message = Message.generate_message({:canceled, :failed})
    assert expected_message == actual_message
  end

  test "generate canceled/retry message" do
    expected_message =
      "This PR was included in a batch that was canceled, it will be automatically retried"

    actual_message = Message.generate_message({:canceled, :retrying})
    assert expected_message == actual_message
  end

  test "generate timeout message" do
    expected_message = "Timed out."
    actual_message = Message.generate_message({:timeout, :failed})
    assert expected_message == actual_message
  end

  test "generate timeout/retry message" do
    expected_message =
      "This PR was included in a batch that timed out, it will be automatically retried"

    actual_message = Message.generate_message({:timeout, :retrying})
    assert expected_message == actual_message
  end

  test "generate merged into master message" do
    expected_message = "Pull request successfully merged into master.\n\nBuild succeeded:"
    actual_message = Message.generate_message({:merged, :squashed, "master", []})
    assert expected_message == actual_message
  end

  test "generate commit message" do
    expected_message = """
    Merge #1 #2

    1: Alpha r=r a=lag

    a

    2: Beta r=s a=leg

    b

    Co-authored-by: foo
    Co-authored-by: bar
    """

    patches = [
      %{
        patch: %{
          pr_xref: 1,
          title: "Alpha",
          body: "a",
          author: %{login: "lag"}
        },
        reviewer: "r"
      },
      %{
        patch: %{
          pr_xref: 2,
          title: "Beta",
          body: "b",
          author: %{login: "leg"}
        },
        reviewer: "s"
      }
    ]

    co_authors = ["foo", "bar"]
    actual_message = Message.generate_commit_message(patches, nil, co_authors)
    assert expected_message == actual_message
  end

  test "cut body" do
    assert "a" == Message.cut_body("abc", "b")
  end

  test "cut body with multiple matches" do
    assert "aa" == Message.cut_body("aabcbd", "b")
  end

  test "cut whole body" do
    assert "" == Message.cut_body("abc", "")
  end

  test "cut body with no match" do
    assert "ac" == Message.cut_body("ac", "b")
  end

  test "cut body with nil text" do
    assert "" == Message.cut_body(nil, "b")
  end

  test "cut commit message bodies" do
    expected_message = """
    Merge #1

    1: Synchronize background and foreground processing r=bill a=pea

    Fixes that annoying bug.

    Co-authored-by: foo
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
      %{
        patch: %{
          pr_xref: 1,
          title: title,
          body: body,
          author: %{login: "pea"}
        },
        reviewer: "bill"
      }
    ]

    co_authors = ["foo"]

    actual_message =
      Message.generate_commit_message(
        patches,
        "\n\n<!-- boilerplate follows -->",
        co_authors
      )

    assert expected_message == actual_message
  end

  test "cut commit message bodies in squash commits" do
    expected_message = """
    Synchronize background and foreground processing (#1)

    Fixes that annoying bug.

    Co-authored-by: B <b@b>
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

    user_email = "a@a"

    pr = %{
      number: 1,
      title: title,
      body: body
    }

    commits = [
      %{author_email: user_email, author_name: "A"},
      %{author_email: "b@b", author_name: "B"},
      %{author_email: user_email, author_name: "A"},
      %{author_email: "b@b", author_name: "B"}
    ]

    actual_message =
      Message.generate_squash_commit_message(
        pr,
        commits,
        user_email,
        "\n\n<!-- boilerplate follows -->"
      )

    assert expected_message == actual_message
  end
end
