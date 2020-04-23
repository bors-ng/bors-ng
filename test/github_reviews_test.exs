defmodule BorsNG.GitHub.GitHubReviewsTest do
  use ExUnit.Case

  doctest BorsNG.GitHub.Reviews

  test "counts an empty list as zero", _ do
    result = BorsNG.GitHub.Reviews.from_json!([])
    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 0, "approvers" => []}
  end

  test "counts an approval", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "APPROVED"
        }
      ])

    assert result == %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0, "approvers" => ["bert"]}
  end

  test "ignore comment-only reviews", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "COMMENTED"
        },
        %{
          "user" => %{"login" => "bert"},
          "state" => "APPROVED"
        },
        %{
          "user" => %{"login" => "bert"},
          "state" => "COMMENTED"
        }
      ])

    assert result == %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0, "approvers" => ["bert"]}
  end

  test "have dismissed reviews cancel everything else", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "APPROVED"
        },
        %{
          "user" => %{"login" => "bert"},
          "state" => "DISMISSED"
        }
      ])

    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 0, "approvers" => []}
  end

  test "counts a change request", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "CHANGES_REQUESTED"
        }
      ])

    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 1, "approvers" => []}
  end

  test "counts the last item (change request)", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "APPROVED"
        },
        %{
          "user" => %{"login" => "bert"},
          "state" => "CHANGES_REQUESTED"
        }
      ])

    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 1, "approvers" => []}
  end

  test "counts the last item (approval)", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "CHANGES_REQUESTED"
        },
        %{
          "user" => %{"login" => "bert"},
          "state" => "APPROVED"
        }
      ])

    assert result == %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0, "approvers" => ["bert"]}
  end

  test "counts separate users", _ do
    result =
      BorsNG.GitHub.Reviews.from_json!([
        %{
          "user" => %{"login" => "bert"},
          "state" => "CHANGES_REQUESTED"
        },
        %{
          "user" => %{"login" => "ernie"},
          "state" => "APPROVED"
        }
      ])

    assert result == %{
             "APPROVED" => 1,
             "CHANGES_REQUESTED" => 1,
             "approvers" => ["ernie"]
           }
  end
end
