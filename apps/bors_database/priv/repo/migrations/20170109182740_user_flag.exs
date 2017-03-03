defmodule BorsNG.Repo.Migrations.UserFlag do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false
    end
  end
end
