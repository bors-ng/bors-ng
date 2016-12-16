defmodule Aelita2.Repo.Migrations.InstallationId do
  use Ecto.Migration

  def change do
  	rename table(:installations), :installation_id, to: :installation_xref
  	rename table(:projects), :repo_id, to: :repo_xref
  	rename table(:projects), :installation, to: :installation_id
  	rename table(:users), :user_id, to: :user_xref
  end
end
