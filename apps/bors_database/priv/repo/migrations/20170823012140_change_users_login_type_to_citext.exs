defmodule BorsNG.Database.Repo.Migrations.ChangeUsersLoginTypeToCitext do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    alter table(:users) do
      modify :login, :citext
    end
  end

  def down do
    alter table(:users) do
      modify :login, :string
    end

    execute "DROP EXTENSION citext"
  end
end
