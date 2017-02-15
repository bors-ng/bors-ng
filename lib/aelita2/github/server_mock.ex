defmodule Aelita2.GitHub.ServerMock do
  use GenServer

  @moduledoc """
  Provides a fake connection to GitHub's REST API.

  This is used for unit testing and when running in a "dev" environment,
  like on a local machine.
  It's basically just a genserver frontend for a big map;
  you can put and get its state,
  and other functions will mutate or read subsets of it.

  For example, I can run `iex -S mix phoenix.server` and do this:

      iex> # Push state to "GitHub"
      iex> alias Aelita2.GitHub
      iex> alias Aelita2.GitHub.ServerMock
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
      ...>     statuses: %{},
      ...>     files: %{}}})
      iex> GitHub.get_open_prs!({{:installation, 91}, 14})
      [
        %Aelita2.GitHub.Pr{
          number: 1,
          title: "Test",
          body: "Mess",
          state: :open,
          base_ref: "master",
          head_sha: "00000001",
          user: %Aelita2.GitHub.User{
            id: 6,
            login: "bors-fanboi",
            avatar_url: "data:image/svg+xml,<svg></svg>"}}]
      iex> # The installation now exists; notify bors about it.
      iex> Aelita2.WebhookController.do_webhook(%{
      ...>   body_params: %{
      ...>     "installation" => %{ "id" => 91 },
      ...>     "sender" => %{
      ...>       "id" => 6,
      ...>       "login" => "bors-fanboi",
      ...>       "avatar_url" => "" },
      ...>     "action" => "created" }}, "github", "integration_installation")
      iex> proj = Aelita2.Repo.get_by!(Aelita2.Project, repo_xref: 14)
      iex> proj.name
      "test/repo"
      iex> # This has also started a (background) sync of all attached patches.
      iex> # Watch it happen in the user interface.
      iex> Aelita2.Syncer.wait_hot_spin(proj.id)
      iex> patch = Aelita2.Repo.get_by!(Aelita2.Patch, pr_xref: 1)
      iex> patch.title
      "Test"
  """

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: Aelita2.GitHub)
  end

  @type tconn :: Aelita2.GitHub.tconn
  @type ttoken :: Aelita2.GitHub.ttoken
  @type trepo :: Aelita2.GitHub.trepo
  @type tuser :: Aelita2.GitHub.User.t

  @type tbranch :: bitstring
  @type tcommit :: bitstring

  @type tstate :: %{
    tconn => %{
      branches: %{ tbranch => tcommit },
      comments: %{ integer => [ bitstring ] },
      statuses: %{ tbranch => %{ bitstring => :open | :closed | :running } },
      files: %{ tbranch => %{ bitstring => bitstring } }
    },
    {:installation, number} => %{
      repos: [ trepo ]
    },
    :users => %{ bitstring => tuser }
  }

  def put_state(state) do
    GenServer.call(Aelita2.GitHub, {:put_state, state})
  end

  def get_state do
    GenServer.call(Aelita2.GitHub, {:get_state})
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

  def do_handle_call(:get_pr, repo_conn, {pr_xref}, state) do
    with({:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, pulls} <- Map.fetch(repo, :pulls),
      do: Map.fetch(pulls, pr_xref))
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_pr}, state}
    end
  end

  def do_handle_call(:get_installation_repos, installation_conn, {}, state) do
    with({:ok, installation} <- Map.fetch(state, installation_conn),
         {:ok, repos} <- Map.fetch(installation, :repos),
      do: {:ok, repos})
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_open_prs}, state}
    end
  end

  def do_handle_call(:get_open_prs, repo_conn, {}, state) do
    with({:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, pulls} <- Map.fetch(repo, :pulls),
      do: {:ok, Map.values(pulls) |> Enum.filter(&(&1.state == :open))})
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_open_prs}, state}
    end
  end

  def do_handle_call(:push, repo_conn, {sha, to}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      branches = %{ branches | to => sha }
      repo = %{ repo | branches: branches }
      state = %{ state | repo_conn => repo }
      {{:ok, sha}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :push}, state}
    end
  end

  def do_handle_call(:copy_branch, repo_conn, {from, to}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      sha = case branches[from] do
        nil -> from
        sha -> sha
      end
      branches = %{ branches | to => sha }
      repo = %{ repo | branches: branches }
      state = %{ state | repo_conn => repo }
      {{:ok, sha}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :copy_branch}, state}
    end
  end

  def do_handle_call(:merge_branch, repo_conn, {%{
    from: from,
    to: to,
    commit_message: _commit_message}}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      base = branches[to]
      head = case branches[from] do
        nil -> from
        head -> head
      end
      nsha = base <> head
      branches = %{ branches | to => nsha }
      repo = %{ repo | branches: branches }
      state = %{ state | repo_conn => repo }
      {{:ok, %{commit: nsha, tree: nsha}}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :merge_branch}, state}
    end
  end

  def do_handle_call(:synthesize_commit, repo_conn, {%{
    branch: branch,
    tree: tree,
    parents: parents,
    commit_message: _commit_message}}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, branches} <- Map.fetch(repo, :branches) do
      nsha = parents
      |> Enum.reverse()
      |> Enum.reduce(&<>/2)
      ^nsha = tree
      branches = %{ branches | branch => nsha }
      repo = %{ repo | branches: branches }
      state = %{ state | repo_conn => repo }
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
      branches = %{ branches | to => sha }
      repo = %{ repo | branches: branches }
      state = %{ state | repo_conn => repo }
      {{:ok, sha}, state}
    end
    |> case do
      {{:ok, _}, _} = res -> res
      _ -> {{:error, :force_push}, state}
    end
  end

  def do_handle_call(:get_commit_status, repo_conn, {sha}, state) do
    with({:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, statuses} <- Map.fetch(repo, :statuses),
      do: {:ok, statuses[sha]})
    |> case do
      {:ok, _} = res -> {res, state}
      _ -> {{:error, :get_commit_status}, state}
    end
  end

  def do_handle_call(:get_file, repo_conn, {branch, path}, state) do
    with({:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, files} <- Map.fetch(repo, :files),
      do: {:ok, files[branch][path]})
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
      repo = %{ repo | comments: comments }
      state = %{ state | repo_conn => repo }
      {:ok, state}
    end
    |> case do
      {:ok, state} -> {:ok, state}
      _ -> {{:error, :post_comment}, state}
    end
  end

  def do_handle_call(:post_commit_status, repo_conn, {sha, status, _}, state) do
    with {:ok, repo} <- Map.fetch(state, repo_conn),
         {:ok, statuses} <- Map.fetch(repo, :statuses) do
      sha_statuses = case Map.has_key?(statuses, sha) do
        false -> %{ "bors" => status }
        true ->
          statuses
          |> Map.fetch!(sha)
          |> Map.put("bors", status)
      end
      statuses = Map.put(statuses, sha, sha_statuses)
      repo = %{ repo | statuses: statuses }
      state = %{ state | repo_conn => repo }
      {:ok, state}
    end
    |> case do
      {:ok, state} -> {:ok, state}
      _ -> {{:error, :post_commit_status}, state}
    end
  end

  def do_handle_call(
    :get_user_by_login, _token, {login}, state
  ) do
    with({:ok, users} <- Map.fetch(state, :users),
      do: {:ok, users[login]})
    |> case do
      {:ok, user} -> {{:ok, user}, state}
      _ -> {{:ok, nil}, state}
    end
  end

end
