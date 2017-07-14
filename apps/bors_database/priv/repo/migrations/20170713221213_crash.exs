defmodule BorsNG.Database.Repo.Migrations.Crash do
  use Ecto.Migration

  def change do
    create table(:crashes) do
      add :project_id, references(:projects, on_delete: :delete_all)
      add :crash, :text
      add :component, :string
      timestamps()
    end
  end
end
