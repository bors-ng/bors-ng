defmodule BorsNG.Repo.Migrations.TimeoutAt do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      add :timeout_at, :integer, default: 0
    end
  end
end
