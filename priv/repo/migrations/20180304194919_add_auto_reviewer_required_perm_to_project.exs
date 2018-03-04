defmodule BorsNG.Database.Repo.Migrations.
          AddAutoReviewerRequiredPermToProject do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :auto_reviewer_required_perm, :string, null: true, default: "admin"
    end
  end
end
