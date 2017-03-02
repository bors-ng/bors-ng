defmodule Aelita2.Repo.Migrations.RemoveType do
  use Ecto.Migration

  def change do
    create table(:installations) do
      add :installation_id, :integer
      timestamps()
    end
    create table(:link_user_project, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :project_id, references(:projects, on_delete: :delete_all)
    end
    alter table(:users) do
      remove :type
    end
    alter table(:projects) do
      remove :type
      remove :owner
      add :installation, references(:installations, on_delete: :delete_all)
    end
  end
end
