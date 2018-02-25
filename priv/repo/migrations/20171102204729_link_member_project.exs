defmodule BorsNG.Database.Repo.Migrations.LinkMemberProject do
  use Ecto.Migration

  def change do
    create table(:link_member_project) do
      add :project_id, references(:projects, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)
    end
    create index(:link_member_project, [:user_id, :project_id],
      name: :link_member_project_user_id_project_id_index, unique: true)
  end
end
