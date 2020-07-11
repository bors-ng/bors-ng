require Logger

defmodule BorsNG.GitHub do
  @moduledoc """
  Wrappers around the GitHub REST API.
  """

  @typedoc """
  An authentication token;
  this may be a raw token (as on oAuth)
  or an installation xref (in which case the server will look it up).
  """
  @type ttoken :: {:installation, number} | {:raw, binary}

  @typedoc """
  A repository connection;
  it packages a repository with the permissions to access it.
  """
  @type tconn :: {ttoken, number} | {ttoken, number}

  @type tuser :: BorsNG.GitHub.User.t()
  @type trepo :: BorsNG.GitHub.Repo.t()
  @type tpr :: BorsNG.GitHub.Pr.t()
  @type tstatus :: :ok | :running | :error
  @type trepo_perm :: :admin | :push | :pull
  @type tuser_repo_perms :: %{admin: boolean, push: boolean, pull: boolean}
  @type tcollaborator :: %{user: tuser, perms: tuser_repo_perms}
  @type tcommitter :: %{name: bitstring, email: bitstring}

  @spec get_pr_files!(tconn, integer) :: [BorsNG.GitHub.File.t()]
  def get_pr_files!(repo_conn, pr_xref) do
    {:ok, pr} = get_pr_files(repo_conn, pr_xref)
    pr
  end

  @spec get_pr_files(tconn, integer) ::
          {:ok, [BorsNG.GitHub.File.t()]} | {:error, term}
  def get_pr_files(repo_conn, pr_xref) do
    GenServer.call(
      BorsNG.GitHub,
      {:get_pr_files, repo_conn, {pr_xref}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec get_pr!(tconn, integer | bitstring) :: BorsNG.GitHub.Pr.t()
  def get_pr!(repo_conn, pr_xref) do
    {:ok, pr} = get_pr(repo_conn, pr_xref)
    pr
  end

  @spec get_pr(tconn, integer | bitstring) ::
          {:ok, BorsNG.GitHub.Pr.t()} | {:error, term}
  def get_pr(repo_conn, pr_xref) do
    GenServer.call(
      BorsNG.GitHub,
      {:get_pr, repo_conn, {pr_xref}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec update_pr!(tconn, BorsNG.GitHub.Pr.t()) :: BorsNG.GitHub.Pr.t()
  def update_pr!(repo_conn, pr) do
    {:ok, pr} = update_pr(repo_conn, pr)
    pr
  end

  @spec update_pr(tconn, BorsNG.GitHub.Pr.t()) ::
          {:ok, BorsNG.GitHub.Pr.t()} | {:error, term}
  def update_pr(repo_conn, pr) do
    GenServer.call(
      BorsNG.GitHub,
      {:update_pr, repo_conn, pr},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec get_pr_commits!(tconn, integer | bitstring) :: [BorsNG.GitHub.Commit.t()]
  def get_pr_commits!(repo_conn, pr_xref) do
    {:ok, commits} = get_pr_commits(repo_conn, pr_xref)
    commits
  end

  @spec get_pr_commits(tconn, integer | bitstring) ::
          {:ok, [BorsNG.GitHub.Commit.t()]} | {:error, term}
  def get_pr_commits(repo_conn, pr_xref) do
    GenServer.call(
      BorsNG.GitHub,
      {:get_pr_commits, repo_conn, {pr_xref}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec get_open_prs!(tconn) :: [tpr]
  def get_open_prs!(repo_conn) do
    {:ok, prs} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_open_prs, repo_conn, {}},
        100_000
      )

    prs
  end

  @spec push!(tconn, binary, binary) :: binary
  def push!(repo_conn, sha, to) do
    {:ok, sha} =
      GenServer.call(
        BorsNG.GitHub,
        {:push, repo_conn, {sha, to}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    sha
  end

  @spec push(tconn, binary, binary) :: {:ok, binary} | {:error, term, term, term}
  def push(repo_conn, sha, to) do
    GenServer.call(
      BorsNG.GitHub,
      {:push, repo_conn, {sha, to}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec get_branch!(tconn, binary) :: %{commit: bitstring, tree: bitstring}
  def get_branch!(repo_conn, from) do
    {:ok, commit} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_branch, repo_conn, {from}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    commit
  end

  @spec delete_branch!(tconn, binary) :: :ok
  def delete_branch!(repo_conn, branch) do
    :ok =
      GenServer.call(
        BorsNG.GitHub,
        {:delete_branch, repo_conn, {branch}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    :ok
  end

  @spec merge_branch!(tconn, %{
          from: bitstring,
          to: bitstring,
          commit_message: bitstring
        }) :: %{commit: binary, tree: binary} | :conflict
  def merge_branch!(repo_conn, info) do
    {:ok, commit} =
      GenServer.call(
        BorsNG.GitHub,
        {:merge_branch, repo_conn, {info}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    commit
  end

  @spec synthesize_commit!(tconn, %{
          branch: bitstring,
          tree: bitstring,
          parents: [bitstring],
          commit_message: bitstring,
          committer: tcommitter | nil
        }) :: binary
  def synthesize_commit!(repo_conn, info) do
    {:ok, sha} =
      GenServer.call(
        BorsNG.GitHub,
        {:synthesize_commit, repo_conn, {info}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    sha
  end

  @spec create_commit!(tconn, %{
          tree: bitstring,
          parents: [bitstring],
          commit_message: bitstring,
          committer: tcommitter | nil
        }) :: binary
  def create_commit!(repo_conn, info) do
    {:ok, sha} =
      GenServer.call(
        BorsNG.GitHub,
        {:create_commit, repo_conn, {info}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    sha
  end

  @spec create_commit(tconn, %{
          tree: bitstring,
          parents: [bitstring],
          commit_message: bitstring,
          committer: tcommitter | nil
        }) :: {:ok, binary} | {:error, term, term}
  def create_commit(repo_conn, info) do
    GenServer.call(
      BorsNG.GitHub,
      {:create_commit, repo_conn, {info}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec force_push!(tconn, binary, binary) :: binary
  def force_push!(repo_conn, sha, to) do
    {:ok, sha} =
      GenServer.call(
        BorsNG.GitHub,
        {:force_push, repo_conn, {sha, to}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    sha
  end

  @spec get_commit_status!(tconn, binary) :: %{
          binary => tstatus
        }
  def get_commit_status!(repo_conn, sha) do
    {:ok, status} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_commit_status, repo_conn, {sha}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    status
  end

  @spec get_labels!(tconn, integer | bitstring) :: [bitstring]
  def get_labels!(repo_conn, issue_xref) do
    {:ok, labels} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_labels, repo_conn, {issue_xref}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    labels
  end

  @spec get_reviews!(tconn, integer | bitstring) :: map
  def get_reviews!(repo_conn, issue_xref) do
    {:ok, labels} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_reviews, repo_conn, {issue_xref}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    labels
  end

  @spec get_commit_reviews!(tconn, integer | bitstring, binary) :: map
  def get_commit_reviews!(repo_conn, issue_xref, sha) do
    {:ok, labels} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_reviews, repo_conn, {issue_xref, sha}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    labels
  end

  @spec get_file!(tconn, binary, binary) :: binary | nil
  def get_file!(repo_conn, branch, path) do
    {:ok, file} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_file, repo_conn, {branch, path}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    file
  end

  @spec post_comment!(tconn, number, binary) :: :ok
  def post_comment!(repo_conn, number, body) do
    :ok =
      GenServer.call(
        BorsNG.GitHub,
        {:post_comment, repo_conn, {number, body}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    :ok
  end

  @spec post_commit_status!(tconn, {binary, tstatus, binary, binary}) :: :ok
  def post_commit_status!(repo_conn, {sha, status, msg, url}) do
    # Auto-retry
    first_try =
      GenServer.call(
        BorsNG.GitHub,
        {:post_commit_status, repo_conn, {sha, status, msg, url}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    case first_try do
      :ok ->
        :ok

      _ ->
        Process.sleep(11)

        :ok =
          GenServer.call(
            BorsNG.GitHub,
            {:post_commit_status, repo_conn, {sha, status, msg, url}},
            Confex.fetch_env!(:bors, :api_github_timeout)
          )
    end

    :ok
  end

  @spec get_user_by_login!(ttoken, binary) :: {:ok, tuser} | :error | nil
  def get_user_by_login!(token, login) do
    {:ok, user} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_user_by_login, token, {String.trim(login)}},
        Confex.fetch_env!(:bors, :api_github_timeout)
      )

    user
  end

  @spec get_team_by_name(tconn, String.t(), String.t()) ::
          {:ok, BorsNG.GitHub.Team.t()} | {:error, String.t()}
  def get_team_by_name(repo_conn, org_name, team_name) do
    GenServer.call(
      BorsNG.GitHub,
      {:get_team_by_name, repo_conn, {org_name, team_name}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec belongs_to_team?(tconn, String.t(), integer) ::
          boolean
  def belongs_to_team?(repo_conn, username, team_id) do
    GenServer.call(
      BorsNG.GitHub,
      {:belongs_to_team, repo_conn, {username, team_id}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec get_collaborators_by_repo(tconn) ::
          {:ok, [tcollaborator]} | :error
  def get_collaborators_by_repo(repo_conn) do
    GenServer.call(
      BorsNG.GitHub,
      {:get_collaborators_by_repo, repo_conn, {}},
      Confex.fetch_env!(:bors, :api_github_timeout)
    )
  end

  @spec get_app!() :: String.t()
  def get_app! do
    {:ok, app_link} =
      GenServer.call(BorsNG.GitHub, :get_app, Confex.fetch_env!(:bors, :api_github_timeout))

    app_link
  end

  @spec get_installation_repos!(ttoken) :: [trepo]
  def get_installation_repos!(token) do
    {:ok, repos} =
      GenServer.call(
        BorsNG.GitHub,
        {:get_installation_repos, token, {}},
        100_000
      )

    repos
  end

  @spec get_installation_list! :: [integer]
  def get_installation_list! do
    {:ok, installations} =
      GenServer.call(
        BorsNG.GitHub,
        :get_installation_list,
        100_000
      )

    installations
  end

  @spec map_state_to_status(binary) :: tstatus
  def map_state_to_status(state) do
    case state do
      "pending" -> :running
      "success" -> :ok
      "failure" -> :error
      "error" -> :error
    end
  end

  @spec map_check_to_status(binary) :: tstatus
  def map_check_to_status(conclusion) do
    case conclusion do
      nil -> :running
      "success" -> :ok
      _ -> :error
    end
  end

  @spec map_status_to_state(tstatus) :: binary
  def map_status_to_state(state) do
    case state do
      :running -> "pending"
      :ok -> "success"
      :error -> "failure"
    end
  end

  @spec map_changed_status(binary) :: binary
  def map_changed_status(check_name) do
    case check_name do
      "Travis CI - Branch" -> "continuous-integration/travis-ci/push"
      check_name -> check_name
    end
  end
end
