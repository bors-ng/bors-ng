defmodule BorsNG.Repo.Migrations.Try do
  use Ecto.Migration

  def change do
    create table(:attempts) do
      add :patch_id, references(:patches, on_delete: :delete_all)
      add :commit, :string
      add :state, :integer
      add :last_polled, :integer
      add :timeout_at, :integer
      timestamps()
    end
    create table(:attempt_statuses) do
      add :attempt_id, references(:attempts, on_delete: :delete_all)
      add :identifier, :string
      add :url, :string
      add :state, :integer
      timestamps()
    end
    alter table(:projects) do
      add :trying_branch, :string, default: "trying"
    end
  end
end
