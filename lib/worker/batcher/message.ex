defmodule BorsNG.Worker.Batcher.Message do
  @moduledoc """
  User-readable strings that go in commit messages and comments.
  """

  def generate_status(:waiting) do
    {"Waiting in queue", :running}
  end

  def generate_status(:canceled) do
    {"Canceled", :error}
  end

  def generate_status(:running) do
    {"Running", :running}
  end

  def generate_status(:ok) do
    {"Build succeeded", :ok}
  end

  def generate_status(:error) do
    {"Build failed", :error}
  end

  def generate_status(:timeout) do
    {"Timed out", :error}
  end

  def generate_status(:conflict) do
    {"Merge conflict", :error}
  end

  def generate_status(:delayed) do
    {"Delayed for higher-priority pull requests", :running}
  end

  def generate_message({:preflight, :waiting}) do
    ":clock1: Waiting for PR status (Github check) to be set, probably by CI. Bors will automatically try to run when all required PR statuses are set."
  end

  def generate_message({:preflight, :ok}) do
    "All preflight checks passed. Batching this PR into the staging branch."
  end

  def generate_message({:preflight, :timeout}) do
    "GitHub status checks took too long to complete, so bors is giving up. You can adjust bors configuration to have it wait longer if you like."
  end

  def generate_message({:preflight, :blocked_labels}) do
    ":-1: Rejected by label"
  end

  def generate_message({:preflight, :pr_status}) do
    ":-1: Rejected by PR status"
  end

  def generate_message({:preflight, :insufficient_approvals}) do
    ":-1: Rejected by too few approved reviews"
  end

  def generate_message({:preflight, :insufficient_up_to_date_approvals}) do
    ":-1: Rejected by too few up-to-date approved reviews (some of the PR reviews are stale)"
  end

  def generate_message({:preflight, :missing_code_owner_approval}) do
    ":-1: Rejected because of missing code owner approval"
  end

  def generate_message({:preflight, :blocked_review}) do
    ":-1: Rejected by code reviews"
  end

  def generate_message({:preflight, :ci_skip}) do
    "Has [ci skip][skip ci][skip netlify], bors build will time out"
  end

  def generate_message(:already_running_review) do
    "Already running a review"
  end

  def generate_message({:config, message}) do
    "Configuration problem:\n#{message}"
  end

  def generate_message({:conflict, :failed}) do
    "Merge conflict."
  end

  def generate_message({:conflict, :retrying}) do
    nil
  end

  def generate_message({:timeout, :failed}) do
    "Timed out."
  end

  def generate_message({:timeout, :retrying}) do
    "This PR was included in a batch that timed out, it will be automatically retried"
  end

  def generate_message({:canceled, :failed}) do
    "Canceled."
  end

  def generate_message({:canceled, :retrying}) do
    "This PR was included in a batch that was canceled, it will be automatically retried"
  end

  def generate_message({:push_failed_non_ff, target_branch}) do
    "This PR was included in a batch that successfully built, but then failed to merge into #{
      target_branch
    } (it was a non-fast-forward update). It will be automatically retried."
  end

  def generate_message({state, statuses}) do
    is_new_year = get_is_new_year()

    msg =
      case state do
        :succeeded when is_new_year -> "Build succeeded!\n\n*And happy new year! 🎉*\n\n"
        :succeeded -> "Build succeeded:"
        :failed -> "Build failed:"
        :retrying -> "Build failed (retrying...):"
      end

    ([msg] ++ Enum.map(statuses, &"  * #{gen_status_link(&1)}"))
    |> Enum.join("\n")
  end

  def generate_message({:merged, :squashed, target_branch, statuses}) do
    status_msg = generate_message({:succeeded, statuses})
    "Pull request successfully merged into #{target_branch}.\n\n#{status_msg}"
  end

  def gen_status_link(status) do
    case status.url do
      nil -> status.identifier
      url -> "[#{status.identifier}](#{url})"
    end
  end

  def generate_squash_commit_message(pr, commits, user_email, cut_body_after) do
    message_body = cut_body(pr.body, cut_body_after)

    co_authors =
      commits
      |> Enum.filter(&(&1.author_email != user_email))
      |> Enum.map(&"Co-authored-by: #{&1.author_name} <#{&1.author_email}>")
      |> Enum.uniq()
      |> Enum.join("\n")

    "#{pr.title} (##{pr.number})\n\n#{message_body}\n\n#{co_authors}\n"
  end

  def generate_commit_message(patch_links, cut_body_after, co_authors) do
    commit_title = Enum.reduce(patch_links, "Merge", &"#{&2} \##{&1.patch.pr_xref}")

    commit_body =
      Enum.reduce(patch_links, "", fn link, acc ->
        body = cut_body(link.patch.body, cut_body_after)

        author =
          case link.patch.author do
            nil -> "[unknown]"
            author -> author.login
          end

        reviewer = link.reviewer
        title = link.patch.title
        number = link.patch.pr_xref

        """
        #{acc}
        #{number}: #{title} r=#{reviewer} a=#{author}

        #{body}
        """
      end)

    co_author_trailers =
      co_authors
      |> Enum.map(&"Co-authored-by: #{&1}")
      |> Enum.join("\n")

    "#{commit_title}\n#{commit_body}\n#{co_author_trailers}\n"
  end

  def cut_body(nil, _), do: ""
  def cut_body(body, nil), do: body

  def cut_body(body, cut) do
    body
    |> String.splitter(cut)
    |> Enum.at(0)
  end

  def generate_bors_toml_error(:parse_failed) do
    "bors.toml: syntax error"
  end

  def generate_bors_toml_error(:empty_config) do
    "bors.toml: does not specify anything to gate on"
  end

  def generate_bors_toml_error(:fetch_failed) do
    "bors.toml: not found"
  end

  def generate_bors_toml_error(:timeout_sec) do
    "bors.toml: expected timeout_sec to be an integer"
  end

  def generate_bors_toml_error(:required_approvals) do
    "bors.toml: expected required_approvals to be an integer"
  end

  def generate_bors_toml_error(:status) do
    "bors.toml: expected status to be a list"
  end

  def generate_bors_toml_error(:blocked_labels) do
    "bors.toml: expected blocked_labels to be a list"
  end

  def get_is_new_year do
    celebrate_new_year = Application.get_env(:bors, :celebrate_new_year)
    %{month: month, day: day} = DateTime.utc_now()

    case {celebrate_new_year, month, day} do
      {true, 12, 31} -> true
      {true, 1, 1} -> true
      {true, 1, 2} -> true
      _ -> false
    end
  end
end
