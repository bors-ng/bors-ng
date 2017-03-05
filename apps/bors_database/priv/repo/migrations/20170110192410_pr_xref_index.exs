defmodule BorsNG.Repo.Migrations.PrXrefIndex do
  use Ecto.Migration

  def change do
    drop index(:patches, [:pr_xref], name: :patches_pr_xref_index)
    create index(:patches, [:pr_xref, :project_id],
      name: :patches_pr_xref_index, unique: true)
  end
end
