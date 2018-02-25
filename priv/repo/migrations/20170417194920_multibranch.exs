defmodule BorsNG.Database.Repo.Migrations.Multibranch do
  use Ecto.Migration

  def up do
    alter table(:batches) do
      add :into_branch, :string, default: "", null: false
    end
    alter table(:attempts) do
      add :into_branch, :string, default: "", null: false
    end
    alter table(:patches) do
      add :into_branch, :string, default: "", null: false
    end
    execute """
      UPDATE batches
      SET into_branch = (
        SELECT master_branch
        FROM projects
        WHERE projects.id = batches.project_id
      )
    """
    execute """
      UPDATE patches
      SET into_branch = (
        SELECT master_branch
        FROM projects
        WHERE projects.id = patches.project_id
      )
    """
    execute """
      UPDATE attempts
      SET into_branch = (
        SELECT master_branch
        FROM projects
        INNER JOIN patches ON (patches.project_id = projects.id)
        WHERE patches.id = attempts.patch_id
      )
    """
    alter table(:projects) do
      remove :master_branch
    end
  end
end
