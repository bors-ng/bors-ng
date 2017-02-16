defmodule Aelita2.UserSocket do
  @moduledoc """
  The router for push notifications.
  It goes from "channel names" to "channel modules",
  and it implements most of the user authentication stuff.
  """

  use Phoenix.Socket

  # Channels
  channel "project_ping:*", Aelita2.ProjectPingChannel

  # Transports
  transport :websocket, Phoenix.Transports.WebSocket, timeout: 45_000
  # transport :longpoll, Phoenix.Transports.LongPoll

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  def connect(%{"token" => token}, socket) do
    vfy = Phoenix.Token.verify(
      socket,
      "channel:current_user",
      token,
      max_age: 60 * 60)
    case vfy do
      {:ok, current_user} ->
        user = Aelita2.Repo.get! Aelita2.User, current_user
        socket = assign(socket, :user, user)
        {:ok, socket}
      {:error, _} ->
        :error
    end
  end

  # Returning `nil` makes this socket anonymous.
  def id(_socket), do: nil
end
