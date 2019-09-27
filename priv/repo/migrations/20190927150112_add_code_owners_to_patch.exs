defmodule BorsNG.Database.Repo.Migrations.AddCodeOwnersToPatch do
  use Ecto.Migration

  def change do
    alter table(:patches) do
      add :code_owners, {:array, :string}, null: true, default: nil
    end
  end
end
