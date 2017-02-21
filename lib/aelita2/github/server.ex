defmodule Aelita2.GitHub.Server do
  use GenServer

  @moduledoc """
  Provides a real connection to GitHub's REST API.
  This doesn't currently do rate limiting, but it will.
  """

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: Aelita2.GitHub)
  end

  @installation_content_type "application/vnd.github.machine-man-preview+json"
  @content_type_raw "application/vnd.github.v3.raw"
  @content_type "application/vnd.github.v3+json"

  @type tconn :: Aelita2.GitHub.tconn
  @type ttoken :: Aelita2.GitHub.ttoken
  @type trepo :: Aelita2.GitHub.trepo
  @type tpr :: Aelita2.GitHub.tpr

  @typedoc """
  The token cache.
  """
  @type ttokenreg :: %{number => {binary, number}}

  @spec config() :: keyword
  defp config do
    :aelita2
    |> Application.get_env(Aelita2.GitHub)
    |> Keyword.merge([ site: "https://api.github.com" ])
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_call({type, {{_, _} = token, repo_xref}, args}, _from, state) do
    {token, state} = raw_token!(token, state)
    res = do_handle_call(type, {token, repo_xref}, args)
    {:reply, res, state}
  end

  def handle_call({type, {_, _} = token, args}, _from, state) do
    {token, state} = raw_token!(token, state)
    res = do_handle_call(type, token, args)
    {:reply, res, state}
  end

  def do_handle_call(:get_pr, repo_conn, {pr_xref}) do
    case get!(repo_conn, "pulls/#{pr_xref}") do
      %{body: raw, status_code: 200} ->
        pr = raw
        |> Poison.decode!()
        |> Aelita2.GitHub.Pr.from_json!()
        {:ok, pr}
      _ ->
        {:error, :get_pr}
    end
  end

  def do_handle_call(:get_open_prs, {{:raw, token}, repo_xref}, {}) do
    {:ok, get_open_prs_!(
      token,
      "#{config()[:site]}/repositories/#{repo_xref}/pulls?state=open",
      [])}
  end

  def do_handle_call(:push, repo_conn, {sha, to}) do
    repo_conn
    |> patch!("git/refs/heads/#{to}", Poison.encode!(%{ "sha": sha }))
    |> case do
      %{body: _, status_code: 200} ->
        {:ok, sha}
      _ ->
        {:error, :push}
    end
  end

  def do_handle_call(:copy_branch, repo_conn, {from, to}) do
    case get!(repo_conn, "branches/#{from}") do
      %{body: raw, status_code: 200} ->
        sha = Poison.decode!(raw)["commit"]["sha"]
        do_handle_call(:force_push, repo_conn, {sha, to})
      _ ->
        {:error, :copy_branch}
    end
  end

  def do_handle_call(:merge_branch, repo_conn, {%{
    from: from,
    to: to,
    commit_message: commit_message}}) do
    msg = %{ "base": to, "head": from, "commit_message": commit_message }
    repo_conn
    |> post!("merges", Poison.encode!(msg))
    |> case do
      %{body: raw, status_code: 201} ->
        data = Poison.decode!(raw)
        res = %{
          commit: data["sha"],
          tree: data["commit"]["tree"]["sha"]
        }
        {:ok, res}
      %{status_code: 409} ->
        {:ok, :conflict}
      _ ->
        {:error, :merge_branch}
    end
  end

  def do_handle_call(:synthesize_commit, repo_conn, {%{
    branch: branch,
    tree: tree,
    parents: parents,
    commit_message: commit_message}}) do
    msg = %{ "parents": parents, "tree": tree, "message": commit_message }
    repo_conn
    |> post!("git/commits", Poison.encode!(msg))
    |> case do
      %{body: raw, status_code: 201} ->
        sha = Poison.decode!(raw)["sha"]
        do_handle_call(:force_push, repo_conn, {sha, branch})
      _ ->
        {:error, :synthesize_commit}
    end
  end

  def do_handle_call(:force_push, repo_conn, {sha, to}) do
    repo_conn
    |> get!("branches/#{to}")
    |> case do
      %{status_code: 404} ->
        msg = %{ "ref": "refs/heads/#{to}", "sha": sha }
        repo_conn
        |> post!("git/refs", Poison.encode!(msg))
        |> case do
          %{status_code: 201} ->
            {:ok, sha}
          _ ->
            {:error, :force_push}
        end
      %{body: raw, status_code: 200} ->
        if sha != Poison.decode!(raw)["commit"]["sha"] do
          msg = %{ "force": true, "sha": sha }
          repo_conn
          |> patch!("git/refs/heads/#{to}", Poison.encode!(msg))
          |> case do
            %{status_code: 200} ->
              {:ok, sha}
            _ ->
              {:error, :force_push}
          end
        else
          {:ok, sha}
        end
      _ ->
        {:error, :force_push}
    end
  end

  def do_handle_call(:get_commit_status, repo_conn, {sha}) do
    repo_conn
    |> get!("commits/#{sha}/status")
    |> case do
      %{body: raw, status_code: 200} ->
        res = Poison.decode!(raw)["statuses"]
        |> Enum.map(&{
          &1["context"],
          Aelita2.GitHub.map_state_to_status(&1["state"])})
        |> Map.new()
        {:ok, res}
      _ ->
        {:error, :get_commit_status}
    end
  end

  def do_handle_call(:get_file, repo_conn, {branch, path}) do
    %{body: raw, status_code: status_code} = get!(
      repo_conn,
      "contents/#{path}",
      [{"Accept", @content_type_raw}],
      [params: [ref: branch]])
    res = case status_code do
      404 -> nil
      200 -> raw
    end
    {:ok, res}
  end

  def do_handle_call(:post_comment, repo_conn, {number, body}) do
    repo_conn
    |> post!("issues/#{number}/comments", Poison.encode!(%{body: body}))
    |> case do
      %{status_code: 201} ->
        :ok
      _ ->
        {:error, :post_comment}
    end
  end

  def do_handle_call(:post_commit_status, repo_conn, {sha, status, msg}) do
    state = Aelita2.GitHub.map_status_to_state(status)
    body = %{state: state, context: "bors", description: msg}
    repo_conn
    |> post!("statuses/#{sha}", Poison.encode!(body))
    |> case do
      %{status_code: 201} ->
        :ok
      _ ->
        {:error, :post_commit_status}
    end
  end

  def do_handle_call(
    :get_user_by_login, {:raw, token}, {login}
  ) do
    "#{config()[:site]}/users/#{login}"
    |> HTTPoison.get!([{"Authorization", "token #{token}"}])
    |> case do
      %{body: raw, status_code: 200} ->
        user = raw
        |> Poison.decode!()
        |> Aelita2.GitHub.User.from_json!()
        {:ok, user}
      %{status_code: 404} ->
        {:ok, nil}
      _ ->
        {:error, :get_user_by_login}
    end
  end

  def do_handle_call(:get_installation_repos, {:raw, token}, {}) do
    {:ok, get_installation_repos_!(
      token,
      "#{config()[:site]}/installation/repositories",
      [])}
  end

  @spec get_installation_repos_!(binary, binary, [trepo]) :: [trepo]

  defp get_installation_repos_!(_, nil, repos) do
    repos
  end

  defp get_installation_repos_!(token, url, append) do
    params = case URI.parse(url).query do
      nil -> []
      qry -> URI.query_decoder(qry) |> Enum.to_list()
    end
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [
        {"Authorization", "token #{token}"},
        {"Accept", @installation_content_type}],
      [params: params])
    repositories = Poison.decode!(raw)["repositories"]
    |> Enum.map(&Aelita2.GitHub.Repo.from_json!/1)
    |> Enum.concat(append)
    next_headers = headers
    |> Enum.filter(&(elem(&1, 0) == "Link"))
    |> Enum.map(&(ExLinkHeader.parse!(elem(&1, 1))))
    |> Enum.filter(&!is_nil(&1.next))
    case next_headers do
      [] -> repositories
      [next] -> get_installation_repos_!(token, next.next.url, repositories)
    end
  end

  @spec get_open_prs_!(binary, binary, [tpr]) :: [tpr]
  defp get_open_prs_!(token, url, append) do
    params = URI.parse(url).query |> URI.query_decoder() |> Enum.to_list()
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}],
      [params: params])
    prs = Poison.decode!(raw)
    |> Enum.map(&Aelita2.GitHub.Pr.from_json!/1)
    |> Enum.concat(append)
    next_headers = headers
    |> Enum.filter(&(elem(&1, 0) == "Link"))
    |> Enum.map(&(ExLinkHeader.parse!(elem(&1, 1))))
    |> Enum.filter(&!is_nil(&1.next))
    case next_headers do
      [] -> prs
      [next] -> get_open_prs_!(token, next.next.url, prs)
    end
  end

  @spec post!(tconn, binary, binary, list) :: map
  defp post!(
    {{:raw, token}, repo_xref},
    path,
    body,
    headers \\ []
    ) do
    HTTPoison.post!(
      "#{config()[:site]}/repositories/#{repo_xref}/#{path}",
      body,
      [{"Authorization", "token #{token}"}] ++ headers)
  end

  @spec patch!(tconn, binary, binary, list) :: map
  defp patch!(
    {{:raw, token}, repo_xref},
    path,
    body,
    headers \\ []
    ) do
    HTTPoison.patch!(
      "#{config()[:site]}/repositories/#{repo_xref}/#{path}",
      body,
      [{"Authorization", "token #{token}"}] ++ headers)
  end

  @spec get!(tconn, binary, list, list) :: map
  defp get!(
    {{:raw, token}, repo_xref},
    path,
    headers \\ [],
    params \\ []
    ) do
    HTTPoison.get!(
      "#{config()[:site]}/repositories/#{repo_xref}/#{path}",
      [{"Authorization", "token #{token}"}] ++ headers,
      params)
  end

  @token_exp 400

  defp installation_config do
    :aelita2
    |> Application.get_env(Aelita2.GitHub)
    |> Keyword.merge(Application.get_env(:aelita2, Aelita2.GitHub.Integration))
    |> Keyword.merge([ site: "https://api.github.com" ])
  end

  @spec get_installation_token!(number) :: binary
  def get_installation_token!(installation_xref) do
    import Joken
    cfg = installation_config()
    pem = JOSE.JWK.from_pem(cfg[:pem])
    jwt_token = %{
      "iat" => current_time(),
      "exp" => current_time() + @token_exp,
      "iss" => cfg[:iss]}
    |> token()
    |> sign(rs256(pem))
    |> get_compact()
    %{body: raw, status_code: 201} = HTTPoison.post!(
      "#{cfg[:site]}/installations/#{installation_xref}/access_tokens",
      "",
      [
        {"Authorization", "Bearer #{jwt_token}"},
        {"Accept", @installation_content_type}])
    Poison.decode!(raw)["token"]
  end

  @doc """
  Given an {:installation, installation_xref},
  look it up in the token cache.
  If it's there, and it's still usable, use it.
  Otherwise, fetch a new one.
  """
  @spec raw_token!(ttoken, ttokenreg) :: {{:raw, binary}, ttokenreg}
  def raw_token!({:installation, installation_xref}, state) do
    now = Joken.current_time()
    case state[installation_xref] do
      {token, expires} when expires < now ->
        {{:raw, token}, state}
      _ ->
        token = get_installation_token!(installation_xref)
        exp = now + (@token_exp / 2) # Give us a little slack to work with.
        state = Map.put(state, installation_xref, {token, exp})
        {{:raw, token}, state}
    end
  end

  def raw_token!({:raw, _} = raw, state) do
    {raw, state}
  end
end
