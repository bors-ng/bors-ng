defmodule BorsNG.GitHub.GitHubReviewsTest do
  use ExUnit.Case

  doctest BorsNG.GitHub.Reviews

  test "counts an empty list as zero", _ do
    result = BorsNG.GitHub.Reviews.from_json!([])
    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 0}
  end

  test "counts an approval", _ do
    result = BorsNG.GitHub.Reviews.from_json!([
      %{
        "user" => %{"id" => 1},
        "state" => "APPROVED",
        "author_association" => "ADMIN"}])
    assert result == %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0}
  end

  test "counts a change request", _ do
    result = BorsNG.GitHub.Reviews.from_json!([
      %{
        "user" => %{"id" => 1},
        "state" => "CHANGES_REQUESTED",
        "author_association" => "ADMIN"}])
    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 1}
  end

  test "counts the last item (change request)", _ do
    result = BorsNG.GitHub.Reviews.from_json!([
      %{
        "user" => %{"id" => 1},
        "state" => "APPROVED",
        "author_association" => "ADMIN"},
      %{
        "user" => %{"id" => 1},
        "state" => "CHANGES_REQUESTED",
        "author_association" => "ADMIN"}])
    assert result == %{"APPROVED" => 0, "CHANGES_REQUESTED" => 1}
  end

  test "counts the last item (approval)", _ do
    result = BorsNG.GitHub.Reviews.from_json!([
      %{
        "user" => %{"id" => 1},
        "state" => "CHANGES_REQUESTED",
        "author_association" => "ADMIN"},
      %{
        "user" => %{"id" => 1},
        "state" => "APPROVED",
        "author_association" => "ADMIN"}])
    assert result == %{"APPROVED" => 1, "CHANGES_REQUESTED" => 0}
  end

  test "counts separate users", _ do
    result = BorsNG.GitHub.Reviews.from_json!([
      %{
        "user" => %{"id" => 1},
        "state" => "CHANGES_REQUESTED",
        "author_association" => "ADMIN"},
      %{
        "user" => %{"id" => 2},
        "state" => "APPROVED",
        "author_association" => "ADMIN"}])
    assert result == %{"APPROVED" => 1, "CHANGES_REQUESTED" => 1}
  end
end
