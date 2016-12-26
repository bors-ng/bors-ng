defmodule Aelita2.Repo.Migrations.Id do
  use Ecto.Migration

  def change do
    rename table(:batches), :project, to: :project_id
    rename table(:patches), :project, to: :project_id
    rename table(:patches), :batch, to: :batch_id
    rename table(:patches), :author, to: :author_id
    rename table(:statuses), :project, to: :project_id
  end
end
