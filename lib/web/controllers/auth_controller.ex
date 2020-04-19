# This file is basically taken verbatim from:
# https://github.com/scrogson/oauth2_example/
defmodule BorsNG.AuthController do
  @moduledoc """
  Routing glue to allow authenticating with GitHub oAuth.
  `BorsNG.Router` ensures that users have to go through here.
  When a user is authenticated, the following items are added to the session

   * `:current_user` the ID of the authenticated user in `BorsNG.User`.
     This controller will create a user if none exists.
   * `:github_access_token` the token to use when accessing the GitHub API.
  """

  use BorsNG.Web, :controller

  alias BorsNG.Database.Repo
  alias BorsNG.Database.User

  @github_api Confex.fetch_env!(:bors, :oauth2)

  @doc """
  This action is reached via `/auth/:provider`
  and redirects to the OAuth2 provider
  based on the chosen strategy.
  """
  def index(conn, %{"provider" => provider}) do
    redirect(conn, external: authorize_url!(provider))
  end

  @doc """
  This action converts a cookie to a socket token.
  Socket tokens are usable for one hour before they must be reset.
  """
  def socket_token(conn, _params) do
    with(
      %{assigns: %{user: %{id: user_id}}} <- conn,
      do:
        (
          token =
            Phoenix.Token.sign(
              conn,
              "channel:current_user",
              user_id
            )

          render(
            conn,
            "socket_token.json",
            token: %{token: token, current_user: user_id}
          )
        )
    )
  end

  def logout(conn, _params) do
    home_url = Confex.fetch_env!(:bors, BorsNG)[:home_url]

    conn
    |> configure_session(drop: true)
    |> redirect(external: home_url)
  end

  @doc """
  This action, which is reached at `/auth/:provider/callback`,
  is the the callback URL that the OAuth2 provider will redirect
  the user back to with a `code`.

  Once here, we will request a permanent access token,
  allowing us to act on the user's behalf through the GitHub REST API.
  We also add a row to our database, if it does not already exist.
  """
  def callback(conn, %{"provider" => provider, "code" => code}) do
    # Exchange an auth code for an access token
    client = get_token!(provider, code)

    # Request the user's data with the access token
    user = get_user!(provider, client)
    avatar = user.avatar_url

    # Create (or reuse) the database record for this user
    current_user_model =
      case Repo.get_by(User, user_xref: user.id) do
        nil ->
          Repo.insert!(%User{
            user_xref: user.id,
            login: user.login
          })

        current_user_model ->
          current_user_model
      end

    # Make sure the login is up-to-date (GitHub users are allowed to change it)
    user_model =
      if current_user_model.login != user.login do
        cs = Ecto.Changeset.change(current_user_model, login: user.login)
        true = cs.valid?
        Repo.update!(cs)
      else
        current_user_model
      end

    redirect_to =
      case get_session(conn, :auth_redirect_to) do
        nil -> page_path(conn, :index)
        redirect_to -> redirect_to
      end

    conn
    |> put_session(:current_user, user_model.id)
    |> put_session(:avatar_url, avatar)
    |> put_session(:github_access_token, client.token.access_token)
    |> redirect(to: redirect_to)
  end

  defp authorize_url!("github"), do: @github_api.authorize_url!
  defp authorize_url!(_), do: raise("No matching provider available")

  defp get_token!("github", code), do: @github_api.get_token!(code: code)
  defp get_token!(_, _), do: raise("No matching provider available")

  defp get_user!("github", client), do: @github_api.get_user!(client)
  defp get_user!(_, _), do: raise("No matching provider available")
end
