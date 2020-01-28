defmodule BorsNG.GitHub.GitHubPrTest do
  use BorsNG.ConnCase

  test "can parse a Poison-decoded JSON *without* mergeable field" do
    result = BorsNG.GitHub.Pr.from_json %{
      "number" => 1,
      "title" => "T",
      "body" => "B",
      "state" => "open",
      "base" => %{"ref" => "OTHER_BRANCH", "repo" => %{"id" => 456}},
      "head" => %{
        "sha" => "B",
        "ref" => "BAR_BRANCH",
        "repo" => %{
          "id" => 345
        },
      },
      "merged_at" => nil,
      "user" => %{
        "id" => 23,
        "login" => "ghost",
        "avatar_url" => "U"}}

    assert result == {:ok, %BorsNG.GitHub.Pr{
      number: 1,
      title: "T",
      body: "B",
      state: :open,
      base_ref: "OTHER_BRANCH",
      head_sha: "B",
      head_ref: "BAR_BRANCH",
      head_repo_id: 345,
      base_repo_id: 456,
      user: %BorsNG.GitHub.User{
        id: 23,
        login: "ghost",
        avatar_url: "U",
      },
      merged: false,
      mergeable: nil
    }}
  end

  test "can parse a Poison-decoded JSON *with* mergeable field" do
    result = BorsNG.GitHub.Pr.from_json %{
      "number" => 1,
      "title" => "T",
      "body" => "B",
      "state" => "open",
      "base" => %{"ref" => "OTHER_BRANCH", "repo" => %{"id" => 456}},
      "head" => %{
        "sha" => "B",
        "ref" => "BAR_BRANCH",
        "repo" => %{
          "id" => 345
        },
      },
      "merged_at" => nil,
      "mergeable" => true,
      "user" => %{
        "id" => 23,
        "login" => "ghost",
        "avatar_url" => "U"}}

    assert result == {:ok, %BorsNG.GitHub.Pr{
      number: 1,
      title: "T",
      body: "B",
      state: :open,
      base_ref: "OTHER_BRANCH",
      head_sha: "B",
      head_ref: "BAR_BRANCH",
      head_repo_id: 345,
      base_repo_id: 456,
      user: %BorsNG.GitHub.User{
        id: 23,
        login: "ghost",
        avatar_url: "U",
      },
      merged: false,
      mergeable: true
    }}
  end
end