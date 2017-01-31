defmodule Aelita2.GitHub.Repo do
  @moduledoc """
  The GitHub repository structure.
  """

  defstruct(
      id: 0,
      name: "",
      owner: %{
        id: 0,
        login: "",
        avatar_url: "",
        type: :user})

  @type t :: %Aelita2.GitHub.Repo{
      id: integer,
      name: bitstring,
      owner: %{
        id: integer,
        login: bitstring,
        avatar_url: bitstring,
        type: :user | :organization}}

  @doc """
  Convert from Poison-decoded JSON to a Repository struct.
  """
  def from_json(%{
    "id" => id,
    "name" => name,
    "owner" => %{
      "id" => owner_id,
      "login" => owner_login,
      "avatar_url" => owner_avatar_url,
      "type" => owner_type}}) do
      {:ok, %Aelita2.GitHub.Repo{
        id: id,
        name: name,
        owner: %{
          id: owner_id,
          login: owner_login,
          avatar_url: owner_avatar_url,
          type: (case owner_type do
            "User" -> :user
            "Organization" -> :organization
          end)}}}
    end

    def from_json(_) do
      :error
    end
end
