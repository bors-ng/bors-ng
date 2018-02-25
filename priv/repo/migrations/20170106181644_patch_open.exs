defmodule BorsNG.Repo.Migrations.PatchOpen do
  use Ecto.Migration

  def change do
    alter table(:patches) do
      add :open, :boolean, default: true
    end
  end
end
