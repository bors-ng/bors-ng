defmodule BorsNG.Database.Repo.Migrations.ChangeUsersLoginTypeToCitext do
  use Ecto.Migration

  @adapter Application.get_env(:bors_database, BorsNG.Database.Repo)[:adapter]

  def up do
    case @adapter do
      Ecto.Adapters.Postgres ->
        execute "CREATE EXTENSION IF NOT EXISTS citext"
        alter table(:users) do
          modify :login, :citext
        end
      Ecto.Adapters.MySQL ->
        :ok
    end
  end

  def down do
    case @adapter do
      Ecto.Adapters.Postgres ->
        alter table(:users) do
          modify :login, :string
        end
        execute "DROP EXTENSION citext"
      Ecto.Adapters.MySQL ->
        :ok
    end
  end
end
