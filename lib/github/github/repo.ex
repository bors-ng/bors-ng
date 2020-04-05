defmodule BorsNG.GitHub.Repo do
  @moduledoc """
  The GitHub repository structure.
  """

  defstruct(
    id: 0,
    name: "",
    private: false,
    owner: %{
      id: 0,
      login: "",
      avatar_url: "",
      type: :user
    }
  )

  @type t :: %BorsNG.GitHub.Repo{
          id: integer,
          name: bitstring,
          private: boolean,
          owner: %{
            id: integer,
            login: bitstring,
            avatar_url: bitstring,
            type: :user | :organization
          }
        }

  def from_json!(json) do
    {:ok, repo} = from_json(json)
    repo
  end

  @doc """
  Convert from Poison-decoded JSON to a Repository struct.
  """
  def from_json(%{
        "id" => id,
        "full_name" => name,
        "private" => private,
        "owner" => %{
          "id" => owner_id,
          "login" => owner_login,
          "avatar_url" => owner_avatar_url,
          "type" => owner_type
        }
      }) do
    {:ok,
     %BorsNG.GitHub.Repo{
       id: id,
       name: name,
       private: private,
       owner: %{
         id: owner_id,
         login: owner_login,
         avatar_url: owner_avatar_url,
         type:
           case owner_type do
             "User" -> :user
             "Organization" -> :organization
           end
       }
     }}
  end

  def from_json(_) do
    :error
  end
end
