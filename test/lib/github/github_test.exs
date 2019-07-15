defmodule ExampleTest do
  use ExUnit.Case
  doctest BorsNG.GitHub

  test "greets the world" do

    repo_conn =  {{:installation, 10}, 595}

    pr = BorsNG.GitHub.get_pr!(repo_conn, 24)

     IO.inspect(pr)

    {:ok, pr_commits} = BorsNG.GitHub.get_pr_commits(repo_conn, pr.number)

    IO.inspect(pr_commits)

    commit_messages = Enum.reduce(pr_commits, "", fn(x, acc) -> "#{x.commit_message}\n#{acc}" end )

    IO.inspect(commit_messages)

    commit_sha = BorsNG.GitHub.green_button_merge!(repo_conn,
             %{pr_number: pr.number,
               pr_title: "#{pr.title} (##{pr.number})",
               sha: "#{pr.head_sha}",
               commit_message: commit_messages}
           )
  end


end