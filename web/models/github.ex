defmodule Aelita2.GitHub do
  @moduledoc """
  Wrapped GitHub APIs
  """

  def config do
    Application.get_env(:aelita2, Aelita2.GitHub)
    |> Keyword.merge([site: "https://api.github.com"])
  end

  @doc """
  List repoes that the oAuth-authenticated user is a contributor to.
  """
  def get_my_repos!(github_access_token) when is_binary(github_access_token) do
    visibility = case config()[:require_visibility] do
      :public -> "public"
      :all -> "all"
    end
    %{body: raw} = HTTPoison.get!(
      "#{config()[:site]}/user/repos",
      [{"Authorization", "token #{github_access_token}"}],
      [params: [{"visibility", visibility}, {"sort", "full_name"}]])
    Poison.decode!(raw) |>
    Enum.map(&%{
      id: &1["id"],
      name: &1["full_name"],
      permissions: %{
        admin: &1["permissions"]["admin"],
        push: &1["permissions"]["push"],
        pull: &1["permissions"]["pull"]
      },
      owner: %{
        id: &1["owner"]["id"],
        login: &1["owner"]["login"],
        avatar_url: &1["owner"]["avatar_url"],
        type: &1["owner"]["type"]}})
  end
end
