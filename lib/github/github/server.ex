defmodule BorsNG.GitHub.Server do
  use GenServer

  @moduledoc """
  Provides a real connection to GitHub's REST API.
  This doesn't currently do rate limiting, but it will.
  """

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: BorsNG.GitHub)
  end

  @installation_content_type "application/vnd.github.machine-man-preview+json"
  @content_type_raw "application/vnd.github.v3.raw"
  @content_type "application/vnd.github.v3+json"

  @type tconn :: BorsNG.GitHub.tconn
  @type ttoken :: BorsNG.GitHub.ttoken
  @type trepo :: BorsNG.GitHub.trepo
  @type tuser :: BorsNG.GitHub.tuser
  @type tpr :: BorsNG.GitHub.tpr
  @type tcollaborator :: BorsNG.GitHub.tcollaborator
  @type tuser_repo_perms :: BorsNG.GitHub.tuser_repo_perms

  @typedoc """
  The token cache.
  """
  @type ttokenreg :: %{number => {binary, number}}

  @spec config() :: keyword
  defp config do
    Confex.fetch_env!(:bors, BorsNG.GitHub.Server)
  end

  @spec site() :: bitstring
  defp site do
    Confex.fetch_env!(:bors, :api_github_root)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_call({type, {{_, _} = token, repo_xref}, args}, _from, state) do
    use_token! token, state, fn token ->
      do_handle_call(type, {token, repo_xref}, args)
    end
  end

  def handle_call({type, {_, _} = token, args}, _from, state) do
    use_token! token, state, fn token ->
      do_handle_call(type, token, args)
    end
  end

  def handle_call(:get_app, _from, state) do
    result = "#{site()}/app"
    |> HTTPoison.get!([
      {"Authorization", "Bearer #{get_jwt_token()}"},
      {"Accept", @installation_content_type}])
    |> case do
      %{body: raw, status_code: 200} ->
        app_link = raw
        |> Poison.decode!()
        |> Map.get("html_url")
        {:ok, app_link}
      _ ->
        {:error, :get_app}
    end
    {:reply, result, state}
  end

  def do_handle_call(:get_pr, repo_conn, {pr_xref}) do
    case get!(repo_conn, "pulls/#{pr_xref}") do
      %{body: raw, status_code: 200} ->
        pr = raw
        |> Poison.decode!()
        |> BorsNG.GitHub.Pr.from_json!()
        {:ok, pr}
      e ->
        {:error, :get_pr, e.status_code, pr_xref}
    end
  end

  def do_handle_call(:get_open_prs, {{:raw, token}, repo_xref}, {}) do
    {:ok, get_open_prs_!(
      token,
      "#{site()}/repositories/#{repo_xref}/pulls?state=open",
      [])}
  end

  def do_handle_call(:push, repo_conn, {sha, to}) do
    repo_conn
    |> patch!("git/refs/heads/#{to}", Poison.encode!(%{"sha": sha}))
    |> case do
      %{body: _, status_code: 200} ->
        {:ok, sha}
      _ ->
        {:error, :push}
    end
  end

  def do_handle_call(:get_branch, repo_conn, {branch}) do
    case get!(repo_conn, "branches/#{branch}") do
      %{body: raw, status_code: 200} ->
        r = Poison.decode!(raw)["commit"]
        {:ok, %{commit: r["sha"], tree: r["commit"]["tree"]["sha"]}}
      _ ->
        {:error, :get_branch}
    end
  end

  def do_handle_call(:delete_branch, repo_conn, {branch}) do
    case delete!(repo_conn, "git/refs/heads/#{branch}") do
      %{status_code: 204} ->
        :ok
      _ ->
        {:error, :delete_branch}
    end
  end

  def do_handle_call(:merge_branch, repo_conn, {%{
    from: from,
    to: to,
    commit_message: commit_message}}) do
    msg = %{"base": to, "head": from, "commit_message": commit_message}
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
      %{status_code: 204} ->
        {:ok, :conflict}
      %{status_code: status_code} ->
        {:error, :merge_branch, status_code}
    end
  end

  def do_handle_call(:synthesize_commit, repo_conn, {%{
    branch: branch,
    tree: tree,
    parents: parents,
    commit_message: commit_message}}) do
    msg = %{"parents": parents, "tree": tree, "message": commit_message}
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
        msg = %{"ref": "refs/heads/#{to}", "sha": sha}
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
          msg = %{"force": true, "sha": sha}
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
          BorsNG.GitHub.map_state_to_status(&1["state"])})
        |> Map.new()
        {:ok, res}
      _ ->
        {:error, :get_commit_status}
    end
  end

  def do_handle_call(:get_labels, repo_conn, {issue_xref}) do
    repo_conn
    |> get!("issues/#{issue_xref}/labels")
    |> case do
      %{body: raw, status_code: 200} ->
        res = Poison.decode!(raw)
        |> Enum.map(fn %{"name" => name} -> name end)
        {:ok, res}
      _ ->
        {:error, :get_labels}
    end
  end

  def do_handle_call(:get_reviews, repo_conn, {issue_xref}) do
    repo_conn
    |> get!("pulls/#{issue_xref}/reviews")
    |> case do
      %{body: raw, status_code: 200} ->
        res = raw
        |> Poison.decode!()
        |> BorsNG.GitHub.Reviews.from_json!()

        {:ok, res}
      _ ->
        {:error, :get_reviews}
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

  def do_handle_call(:post_commit_status, repo_conn, {sha, status, msg, url}) do
    state = BorsNG.GitHub.map_status_to_state(status)
    body = %{state: state, context: "bors", description: msg, target_url: url}
    repo_conn
    |> post!("statuses/#{sha}", Poison.encode!(body))
    |> case do
      %{status_code: 201} ->
        :ok
      _ ->
        {:error, :post_commit_status}
    end
  end

  def do_handle_call(:get_collaborators_by_repo, {{:raw, token}, repo_xref},
                     {}) do
    get_collaborators_by_repo_(
      token,
      "#{site()}/repositories/#{repo_xref}/collaborators",
      [])
  end

  def do_handle_call(
    :get_user_by_login, {:raw, token}, {login}
  ) do
    "#{site()}/users/#{login}"
    |> HTTPoison.get!([{"Authorization", "token #{token}"}])
    |> case do
      %{body: raw, status_code: 200} ->
        user = raw
        |> Poison.decode!()
        |> BorsNG.GitHub.User.from_json!()
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
      "#{site()}/installation/repositories",
      [])}
  end

  @spec get_installation_repos_!(binary, binary, [trepo]) :: [trepo]
  defp get_installation_repos_!(_, nil, repos) do
    repos
  end

  defp get_installation_repos_!(token, url, append) do
    params = get_url_params(url)
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [
        {"Authorization", "token #{token}"},
        {"Accept", @installation_content_type}],
      [params: params])
    repositories = Poison.decode!(raw)["repositories"]
    |> Enum.map(&BorsNG.GitHub.Repo.from_json!/1)
    |> Enum.concat(append)
    next_headers = get_next_headers(headers)
    case next_headers do
      [] -> repositories
      [next] -> get_installation_repos_!(token, next.next.url, repositories)
    end
  end

  @spec get_open_prs_!(binary, binary, [tpr]) :: [tpr]
  defp get_open_prs_!(token, url, append) do
    params = get_url_params(url)
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}],
      [params: params])
    prs = Poison.decode!(raw)
    |> Enum.map(&BorsNG.GitHub.Pr.from_json!/1)
    |> Enum.concat(append)
    next_headers = get_next_headers(headers)
    case next_headers do
      [] -> prs
      [next] -> get_open_prs_!(token, next.next.url, prs)
    end
  end

  @spec extract_user_repo_perms(map()) :: tuser_repo_perms
  defp extract_user_repo_perms(data) do
    Map.new(["admin", "push", "pull"], fn perm ->
      {String.to_atom(perm), !!data["permissions"][perm]}
    end)
  end

  @spec get_collaborators_by_repo_(binary, binary, [tcollaborator]) ::
    {:ok, [tcollaborator]} | {:error, :get_collaborators_by_repo}
  def get_collaborators_by_repo_(token, url, append) do
    params = get_url_params(url)
    url
    |> HTTPoison.get(
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}],
      [params: params])
    |> case do
      {:ok, %{body: raw, status_code: 200, headers: headers}} ->
        users = raw
        |> Poison.decode!()
        |> Enum.map(fn user ->
          %{user: BorsNG.GitHub.User.from_json!(user),
            perms: extract_user_repo_perms(user)}
        end)
        |> Enum.concat(append)
        next_headers = get_next_headers(headers)
        case next_headers do
          [] ->
            {:ok, users}
          [next] ->
            get_collaborators_by_repo_(token, next.next.url, users)
        end
      error ->
        IO.inspect(error)
        {:error, :get_collaborators_by_repo}
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
      "#{site()}/repositories/#{repo_xref}/#{path}",
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
      "#{site()}/repositories/#{repo_xref}/#{path}",
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
      "#{site()}/repositories/#{repo_xref}/#{path}",
      [{"Authorization", "token #{token}"}] ++ headers,
      params)
  end

  @spec delete!(tconn, binary, list, list) :: map
  defp delete!(
    {{:raw, token}, repo_xref},
    path,
    headers \\ [],
    params \\ []
    ) do
    HTTPoison.delete!(
      "#{site()}/repositories/#{repo_xref}/#{path}",
      [{"Authorization", "token #{token}"}] ++ headers,
      params)
  end

  defp get_next_headers(headers) do
    headers
    |> Enum.filter(&(elem(&1, 0) == "Link"))
    |> Enum.map(&(ExLinkHeader.parse!(elem(&1, 1))))
    |> Enum.filter(&!is_nil(&1.next))
  end

  defp get_url_params(url) do
    case URI.parse(url).query do
      nil -> []
      qry -> URI.query_decoder(qry) |> Enum.to_list()
    end
  end

  @token_exp 60

  @spec get_installation_token!(number) :: binary
  def get_installation_token!(installation_xref) do
    jwt_token = get_jwt_token()
    %{body: raw, status_code: 201} = HTTPoison.post!(
      "#{site()}/installations/#{installation_xref}/access_tokens",
      "",
      [
        {"Authorization", "Bearer #{jwt_token}"},
        {"Accept", @installation_content_type}])
    Poison.decode!(raw)["token"]
  end

  def get_jwt_token do
    import Joken
    cfg = config()
    pem = JOSE.JWK.from_pem(cfg[:pem])
    %{
      "iat" => current_time(),
      "exp" => current_time() + @token_exp,
      "iss" => cfg[:iss]}
    |> token()
    |> sign(rs256(pem))
    |> get_compact()
  end

  @doc """
  Uses a token from the cache, or, if the request fails,
  retry without using the cached token.
  """
  @spec use_token!(ttoken, ttokenreg, ((ttoken) -> term)) ::
    {:reply, term, ttokenreg}
  def use_token!({:installation, installation_xref} = token, state, fun) do
    {token, state} = raw_token!(token, state)
    result = fun.(token)
    case result do
      {:ok, _} -> {:reply, result, state}
      :ok -> {:reply, result, state}
      _ ->
        state = Map.delete(state, installation_xref)
        {token, state} = raw_token!(token, state)
        result = fun.(token)
        {:reply, result, state}
    end
  end
  def use_token!(token, state, fun) do
    {token, state} = raw_token!(token, state)
    result = fun.(token)
    {:reply, result, state}
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
      {token, issued} when issued + @token_exp > now ->
        {{:raw, token}, state}
      _ ->
        token = get_installation_token!(installation_xref)
        state = Map.put(state, installation_xref, {token, now})
        {{:raw, token}, state}
    end
  end
  def raw_token!({:raw, _} = raw, state) do
    {raw, state}
  end
end
