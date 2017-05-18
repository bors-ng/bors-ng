defmodule BorsNG.Repo.Migrations.CreateProject do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :repo_xref, :integer
      add :type, :string
      add :name, :string

      timestamps()
    end

  end
end
