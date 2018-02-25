defmodule BorsNG.Database.Repo.Migrations.AddPriorityToPatchesAndBatches do
  use Ecto.Migration

  def change do
    alter table(:patches) do
      add :priority, :integer, null: false, default: 0
    end

    alter table(:batches) do
      add :priority, :integer, null: false, default: 0
    end
  end
end
