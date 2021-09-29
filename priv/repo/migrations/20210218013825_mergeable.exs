defmodule BorsNG.Database.Repo.Migrations.Mergeable do
  use Ecto.Migration

  def change do
    alter table(:patches) do
      add :is_mergeable, :boolean, default: true
      add :is_draft, :boolean, default: false
    end
  end
end
