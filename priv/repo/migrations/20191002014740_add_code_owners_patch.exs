defmodule BorsNG.Database.Repo.Migrations.AddCodeOwnersPatch do
  use Ecto.Migration

  def change do
    create table(:code_owner_reviewers) do
      add :name, :text
    end
    
    create index(:code_owner_reviewers, [:name], 
      name: :code_owner_reviewer_name_index, unique: true)

    create table(:link_patch_code_owner_reviewers) do
      add :patch_id, references(:patches, on_delete: :delete_all)
      add :code_owner_reviewer_id, references(:code_owner_reviewers, on_delete: :delete_all)
    end

    alter table(:patches) do
      add :code_owners, references(:code_owner_reviewers, on_delete: :delete_all)
    end
  end
end
