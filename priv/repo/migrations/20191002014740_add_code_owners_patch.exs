defmodule BorsNG.Database.Repo.Migrations.AddCodeOwnersPatch do
  use Ecto.Migration

  def change do
    create table(:code_owners) do
      add :name, :text
    end
    
    create index(:code_owners, [:name], 
      name: :code_owners_name_index, unique: true)

    create table(:link_patch_code_owners) do
      add :patch_id, references(:patches, on_delete: :delete_all)
      add :code_owners_id, references(:code_owners, on_delete: :delete_all)
    end

    alter table(:patches) do
      add :code_owners, references(:code_owners, on_delete: :delete_all)
    end
  end
end
