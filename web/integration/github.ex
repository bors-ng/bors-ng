defmodule Aelita2.Integration.GitHub do
  @moduledoc """
  Wrappers for accessing the GitHub Integration API.
  """

  @content_type "application/vnd.github.machine-man-preview+json"

  # Get a repository by ID:
  # https://api.github.com/repositories/59789129

  # Public API

  def config do
    Application.get_env(:aelita2, Aelita2.Integration.GitHub)
    |> Keyword.merge([site: "https://api.github.com"])
  end

  def get_installation_token!() do
    import Joken
    cfg = config()
    pem = JOSE.JWK.from_binary(cfg.pem)
    jwt_token = token()
    |> with_iss(cfg.iss)
    |> sign(rs256(pem))
    |> get_compact()
    %{body: raw} = HTTPoison.post!(
      "#{cfg[:site]}/installations/#{cfg[:iss]}/access_tokens",
      "",
      [{"Authorization", "Bearer #{jwt_token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)["token"]
  end
end
