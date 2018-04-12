defmodule BorsNG.Database.Repo.Migrations.AddLog do
  use Ecto.Migration

  def change do
    create table(:log) do
      add :patch_id, references(:patches, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)
      add :cmd, :binary
      timestamps()
    end
  end
end
