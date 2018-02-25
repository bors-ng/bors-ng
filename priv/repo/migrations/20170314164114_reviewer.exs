defmodule BorsNG.Database.Repo.Migrations.Reviewer do
  use Ecto.Migration

  def change do
    alter table(:link_patch_batch) do
      add :reviewer, :string
    end
  end
end
