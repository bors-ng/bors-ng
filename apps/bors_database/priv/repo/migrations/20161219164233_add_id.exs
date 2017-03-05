defmodule BorsNG.Repo.Migrations.AddId do
  use Ecto.Migration

  def change do
    alter table(:link_user_project) do
      add :id, :serial, [primary_key: true]
    end
  end
end
