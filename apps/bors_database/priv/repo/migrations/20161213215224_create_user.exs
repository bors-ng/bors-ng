defmodule BorsNG.Repo.Migrations.CreateUser do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :user_id, :integer
      add :login, :string
      add :type, :string

      timestamps()
    end

  end
end
