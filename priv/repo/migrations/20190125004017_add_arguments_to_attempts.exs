defmodule BorsNG.Database.Repo.Migrations.AddArgumentsToPatch do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :arguments, :string, null: false, default: ""
    end
  end
end
