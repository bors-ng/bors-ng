defmodule BorsNG.Repo.Migrations.StatusYml do
  use Ecto.Migration

  def change do
    alter table(:statuses) do
      remove :project_id
      add :batch_id, references(:batches, on_delete: :delete_all)
    end
    alter table(:patches) do
      remove :batch_id
    end
    create table(:link_patch_batch) do
      add :patch_id, references(:patches, on_delete: :delete_all)
      add :batch_id, references(:batches, on_delete: :delete_all)
    end
  end
end
