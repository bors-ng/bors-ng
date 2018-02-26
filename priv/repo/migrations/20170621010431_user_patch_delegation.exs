defmodule BorsNG.Database.Repo.Migrations.UserPatchDelegation do
  use Ecto.Migration

  def change do
    create table(:user_patch_delegations) do
      add :patch_id, references(:patches, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)
      timestamps()
    end
  end
end
