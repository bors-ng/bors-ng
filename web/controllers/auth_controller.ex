# This file is basically taken verbatim from:
# https://github.com/scrogson/oauth2_example/blob/master/web/controllers/auth_controller.ex
defmodule Aelita2.AuthController do
  use Aelita2.Web, :controller

  alias Aelita2.User

  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]

  @doc """
  This action is reached via `/auth/:provider` and redirects to the OAuth2 provider
  based on the chosen strategy.
  """
  def index(conn, %{"provider" => provider}) do
    redirect conn, external: authorize_url! provider
  end

  def logout(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  @doc """
  This action is reached via `/auth/:provider/callback` is the the callback URL that
  the OAuth2 provider will redirect the user back to with a `code` that will
  be used to request an access token. The access token will then be used to
  access protected resources on behalf of the user.
  """
  def callback(conn, %{"provider" => provider, "code" => code}) do
    # Exchange an auth code for an access token
    client = get_token! provider, code

    # Request the user's data with the access token
    user = get_user! provider, client
    false = is_nil(user.id)

    # Create (or reuse) the database record for this user
    maybe_user_model = Repo.get_by User, user_xref: user.id
    current_user_model =
      if is_nil(maybe_user_model) do
        Repo.insert! %User{
          user_xref: user.id,
          login: user.login}
      else
        maybe_user_model
      end

    # Make sure the login is up-to-date (GitHub users are allowed to change it)
    user_model =
      if current_user_model.login != user.login do
        cs = Ecto.Changeset.change current_user_model, login: user.login
        true = cs.valid?
        Repo.update! cs
      else
        current_user_model
      end

    redirect_to = get_session(conn, :auth_redirect_to)
    redirect_to = if is_nil(redirect_to) do
      page_path(conn, :index)
    else
      redirect_to
    end

    conn
    |> put_session(:current_user, user_model.id)
    |> put_session(:github_access_token, client.token.access_token)
    |> redirect(to: redirect_to)
  end

  defp authorize_url!("github"), do: @github_api.OAuth2.authorize_url!
  defp authorize_url!(_), do: raise "No matching provider available"

  defp get_token!("github", code), do: @github_api.OAuth2.get_token! code: code
  defp get_token!(_, _), do: raise "No matching provider available"

  defp get_user!("github", client) do
    %{body: user} = @github_api.OAuth2.get_user! client
    %{id: user["id"], login: user["login"]}
  end
end
