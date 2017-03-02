defmodule Aelita2.Repo.Migrations.CreateProject do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :repo_id, :integer
      add :type, :string
      add :name, :string
      add :owner, references(:users, on_delete: :nothing)

      timestamps()
    end
    create index(:projects, [:owner])

  end
end
