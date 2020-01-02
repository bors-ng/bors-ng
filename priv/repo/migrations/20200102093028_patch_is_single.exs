defmodule BorsNG.Database.Repo.Migrations.PatchIsSingle do
  use Ecto.Migration

  def change do
    alter table(:patches) do
      add :is_single, :boolean, default: false
    end
  end
end
