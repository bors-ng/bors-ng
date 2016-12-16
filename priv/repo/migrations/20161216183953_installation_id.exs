defmodule Aelita2.Repo.Migrations.InstallationId do
  use Ecto.Migration

  def change do
  	rename table(:installation), :installation_id, to: :installation_xref
  	rename table(:project), :repo_id, to: :repo_xref
  	rename table(:project), :installation, to: :installation_id
  end
end
