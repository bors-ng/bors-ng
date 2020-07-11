defmodule BorsNG.GitHub.ServerMock do
  use GenServer

  @moduledoc """
  Provides a fake connection to GitHub's REST API.

  This is used for unit testing and when running in a "dev" environment,
  like on a local machine.
  It's basically just a genserver frontend for a big map;
  you can put and get its state,
  and other functions will mutate or read subsets of it.

  For example, I can run `iex -S mix phx.server` and do this:

      iex> # Push state to "GitHub"
      iex> alias BorsNG.GitHub
      iex> alias BorsNG.GitHub.ServerMock
      iex> ServerMock.put_state(%{
      ...>   {:installation, 91} => %{ repos: [
      ...>     %GitHub.Repo{
      ...>       id: 14,
      ...>       name: "test/repo",
      ...>       owner: %{
      ...>         id: 6,
      ...>         login: "bors-fanboi",
      ...>         avatar_url: "data:image/svg+xml,<svg></svg>",
      ...>         type: :user
      ...>       }}
      ...>   ] },
      ...>   {{:installation, 91}, 14} => %{
      ...>     branches: %{},
      ...>     commits: %{},
      ...>     comments: %{1 => []},
      ...>     pulls: %{
      ...>       1 => %GitHub.Pr{
      ...>         number: 1,
      ...>         title: "Test",
      ...>         body: "Mess",
      ...>         state: :open,
      ...>         base_ref: "master",
      ...>         head_sha: "00000001",
      ...>         user: %GitHub.User{
      ...>           id: 6,
      ...>           login: "bors-fanboi",
      ...>           avatar_url: "data:image/svg+xml,<svg></svg>"}}},
      ...>     pr_commits: %{
      ...>       1 => [
      ...>         %GitHub.Commit{
      ...>           sha: "00000001",
      ...>           author_name: "Bors Fanboi",
      ...>           author_email: "bors-fanboi@example.com"}
      ...>       ] },
      ...>     statuses: %{},
      ...>     files: %{}}})
      iex> GitHub.get_open_prs!({{:installation, 91}, 14})
      [
        %BorsNG.GitHub.Pr{
          number: 1,
          title: "Test",
          body: "Mess",
          state: :open,
          base_ref: "master",
          head_sha: "00000001",
          user: %BorsNG.GitHub.User{
            id: 6,
            login: "bors-fanboi",
            avatar_url: "data:image/svg+xml,<svg></svg>"}}]
  """

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: BorsNG.GitHub)
  end

  @type tconn :: BorsNG.GitHub.tconn()
  @type ttoken :: BorsNG.GitHub.ttoken()
  @type trepo :: BorsNG.GitHub.trepo()
  @type tuser :: BorsNG.GitHub.User.t()
  @type tcollaborator :: BorsNG.GitHub.tcollaborator()

  @type tbranch :: bitstring
  @type tcommit :: bitstring

  @type tsynthesized :: %{
          commit_message: bitstring,
          parents: [bitstring]
        }

  @type tstate :: %{
          tconn => %{
            branches: %{tbranch => tcommit},
            comments: %{integer => [bitstring]},
            commits: %{bitstring => tsynthesized},
            statuses: %{tbranch => %{bitstring => :open | :closed | :running}},
            files: %{tbranch => %{bitstring => bitstring}},
            collaborators: [tcollaborator]
          },
          {:installation, number} => %{
            repos: [trepo]
          },
          :users => %{bitstring => tuser},
          :merge_conflict => integer
        }

  def put_state(state) do
    GenServer.call(BorsNG.GitHub, {:put_state, state})
  end

  def get_state do
    GenServer.call(BorsNG.GitHub, {:get_state})
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_call({:put_state, state}, _from, _) do
    {:reply, :ok, state}
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_call({type, t, args}, _from, state) do
    {res, state} = do_handle_call(type, t, args, state)
    {:reply, res, state}
  end

  def handle_call(:get_app, _from, state) do
    {:reply, {:ok, "https://github.com/apps/bors-foobar"}, state}
  end

  def handle_call(:get_installation_list, _from, state) do
    list =
      state
      |> Enum.flat_map(fn
        {{{:installation, installation_number}, _repo_number}, _data} ->
          [installation_number]

        {{:installation, installation_number}, _data} ->
          [installation_number]

        _ ->
          []
      end)
      |> Enum.uniq()

    {:reply, {:ok, list}, state}
  end

  def do_handle_call(:get_team_by_name, repo_conn, {org_name, team}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, teams} <- Map.fetch(repo, :teams),
      {:ok, org} <- Map.fetch(teams, org_name),
      do: Map.fetch(org, team)
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_pr}, state}
    end
  end

  def do_handle_call(:get_pr, repo_conn, {pr_xref}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, pulls} <- Map.fetch(repo, :pulls),
      do: Map.fetch(pulls, pr_xref)
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_pr}, state}
    end
  end

  def do_handle_call(:get_pr_files, repo_conn, {_pr_xref}, state) do
    files =
      with {:ok, repo} <- Map.fetch(state, repo_conn),
           {:ok, files} <- Map.fetch(repo, :files) do
        Enum.map(files["Z"], fn {k, _} ->
          %BorsNG.GitHub.File{filename: k}
        end)
      else
        _ -> {{:error, :get_pr_files}, state}
      end

    {{:ok, files}, state}
  end

  def do_handle_call(:get_pr_commits, repo_conn, {pr_xref}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, pr_commits} <- Map.fetch(repo, :pr_commits),
      do: Map.fetch(pr_commits, pr_xref)
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_pr_commits}, state}
    end
  end

  def do_handle_call(:get_installation_repos, installation_conn, {}, state) do
    with(
      {:ok, installation} <- Map.fetch(state, installation_conn),
      {:ok, repos} <- Map.fetch(installation, :repos),
      do: {:ok, repos}
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_open_prs}, state}
    end
  end

  def do_handle_call(:get_open_prs, repo_conn, {}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, pulls} <- Map.fetch(repo, :pulls),
      do: {:ok, Map.values(pulls) |> Enum.filter(&(&1.state == :open))}
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_open_prs}, state}
    end
  end

  def do_handle_call(:push, repo_conn, {sha, to}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches),
         push_errors <- Map.get(repo, :push_errors, %{}) do
      case Map.fetch(push_errors, to) do
        {:ok, error} ->
          {{:error, :push, error[:error_code], error[:response]}, state}

        _ ->
          branches = %{branches | to => sha}
          repo = %{repo | branches: branches}
          state = %{state | repo_conn => repo}
          {{:ok, sha}, state}
      end
    end
    |> case do
      {{:ok, _}, _} = res -> res
      {{:error, :push, _, _}, _} = res -> res
      _ -> {{:error, :push}, state}
    end
  end

  def do_handle_call(:get_branch, repo_conn, {from}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      sha =
        case branches[from] do
          nil -> from
          sha -> sha
        end

      {{:ok, %{commit: sha, tree: sha}}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :get_branch}, state}
    end
  end

  def do_handle_call(:delete_branch, repo_conn, {branch}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      branches = Map.delete(branches, branch)
      repo = %{repo | branches: branches}
      state = %{state | repo_conn => repo}
      {:ok, state}
    end
    |> case do
      {:ok, _} = res -> res
      _ -> {{:error, :get_branch}, state}
    end
  end

  def do_handle_call(:merge_branch, _, _, %{merge_conflict: 0} = state) do
    {{:ok, :conflict}, state}
  end

  def do_handle_call(:merge_branch, repo_conn, params, %{merge_conflict: n} = state)
      when is_integer(n) do
    {result, state} =
      do_handle_call(
        :merge_branch,
        repo_conn,
        params,
        %{state | :merge_conflict => nil}
      )

    {result, %{state | :merge_conflict => n - 1}}
  end

  def do_handle_call(
        :merge_branch,
        repo_conn,
        {%{
           from: from,
           to: to,
           commit_message: _commit_message
         }},
        state
      ) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      base = branches[to]

      head =
        case branches[from] do
          nil -> from
          head -> head
        end

      nsha = base <> head
      branches = %{branches | to => nsha}
      repo = %{repo | branches: branches}
      state = %{state | repo_conn => repo}
      {{:ok, %{commit: nsha, tree: nsha}}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :merge_branch}, state}
    end
  end

  def do_handle_call(
        :synthesize_commit,
        repo_conn,
        {%{
           branch: branch,
           tree: tree,
           parents: parents,
           commit_message: commit_message,
           committer: _committer
         }},
        state
      ) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches),
         {:ok, commits} <- Map.fetch(repo, :commits) do
      nsha =
        parents
        |> Enum.reverse()
        |> Enum.reduce(&<>/2)

      ^nsha = tree

      commits =
        Map.put(commits, nsha, %{
          parents: parents,
          commit_message: commit_message
        })

      branches = Map.put(branches, branch, nsha)
      repo = %{repo | branches: branches}
      repo = %{repo | commits: commits}
      state = %{state | repo_conn => repo}
      {{:ok, nsha}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :synthesize_commit}, state}
    end
  end

  def do_handle_call(:force_push, repo_conn, {sha, to}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      branches = %{branches | to => sha}
      repo = %{repo | branches: branches}
      state = %{state | repo_conn => repo}
      {{:ok, sha}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :force_push}, state}
    end
  end

  def do_handle_call(:get_commit_status, repo_conn, {sha}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, statuses} <- Map.fetch(repo, :statuses),
      do: {:ok, statuses[sha] || %{}}
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_commit_status}, state}
    end
  end

  def do_handle_call(:get_labels, repo_conn, {issue_xref}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, labels} <- Map.fetch(repo, :labels),
      do: {:ok, labels[issue_xref]}
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:ok, []}, state}
    end
  end

  def do_handle_call(:get_reviews, repo_conn, {issue_xref, sha}, state) do
    review_type =
      if is_nil(sha) do
        :reviews
      else
        :up_to_date_reviews
      end

    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, reviews} <- Map.fetch(repo, review_type),
      do: {:ok, reviews[issue_xref]}
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:ok, %{"APPROVED" => 0, "CHANGES_REQUESTED" => 0}}, state}
    end
  end

  def do_handle_call(:get_reviews, repo_conn, {issue_xref}, state) do
    do_handle_call(:get_reviews, repo_conn, {issue_xref, nil}, state)
  end

  def do_handle_call(:get_file, repo_conn, {branch, path}, state) do
    with(
      {:ok, repo} <- Map.fetch(state, repo_conn),
      {:ok, files} <- Map.fetch(repo, :files),
      do: {:ok, files[branch][path]}
    )
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_file}, state}
    end
  end

  def do_handle_call(:post_comment, repo_conn, {number, body}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, comments} <- Map.fetch(repo, :comments),
         {:ok, c} <- Map.fetch(comments, number) do
      c = [body | c]
      comments = %{comments | number => c}
      repo = %{repo | comments: comments}
      state = %{state | repo_conn => repo}
      {:ok, state}
    end
    |> case do
      {:ok, state} -> {:ok, state}
      _ -> {{:error, :post_comment}, state}
    end
  end

  def do_handle_call(
        :post_commit_status,
        repo_conn,
        {sha, status, _, _},
        state
      ) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, statuses} <- Map.fetch(repo, :statuses) do
      sha_statuses =
        case Map.has_key?(statuses, sha) do
          false ->
            %{"bors" => status}

          true ->
            statuses
            |> Map.fetch!(sha)
            |> Map.put("bors", status)
        end

      statuses = Map.put(statuses, sha, sha_statuses)
      repo = %{repo | statuses: statuses}
      state = %{state | repo_conn => repo}
      {:ok, state}
    end
    |> case do
      {:ok, state} -> {:ok, state}
      _ -> {{:error, :post_commit_status}, state}
    end
  end

  def do_handle_call(:get_collaborators_by_repo, repo_conn, {}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, users} <- Map.fetch(repo, :collaborators) do
      {{:ok, users}, state}
    else
      _ ->
        {{:error, :get_collaborators_by_repo}, state}
    end
  end

  def do_handle_call(
        :get_user_by_login,
        _token,
        {login},
        state
      ) do
    with(
      {:ok, users} <- Map.fetch(state, :users),
      do: {:ok, users[login]}
    )
    |> case do
      {:ok, user} -> {{:ok, user}, state}
      _ -> {{:ok, nil}, state}
    end
  end
end
