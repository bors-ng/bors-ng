defmodule BorsNG.Database.RepoPostgres.Migrations.AddHooksTable do
  use Ecto.Migration

  def change do
    create table(:hooks) do
      add :batch_id, references(:batches, on_delete: :delete_all)
      add :identifier, :string
      add :index, :integer
      add :url, :string
      add :state, :integer
      timestamps()
    end
  end
end
