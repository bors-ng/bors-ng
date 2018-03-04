defmodule BorsNG.Database.Repo.Migrations.AddAutoMemberRequiredPermToProject do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :auto_member_required_perm, :string, null: true, default: nil
    end
  end
end
