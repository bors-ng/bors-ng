defmodule BorsNG.Database.Repo.Migrations.DoNotSyncUsersByDefault do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      remove :auto_reviewer_required_perm
      add :auto_reviewer_required_perm, :string, null: true, default: nil
    end
  end
end
