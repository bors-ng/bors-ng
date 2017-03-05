defmodule BorsNG.Repo.Migrations.Constraints do
  use Ecto.Migration

  def change do
    create index(:batches, [:commit],
      name: :batches_commit_index, unique: true)
    create index(:users, [:user_xref],
      name: :users_user_xref_index, unique: true)
    create index(:installations, [:installation_xref],
      name: :installations_installation_xref_index, unique: true)
    create index(:patches, [:pr_xref],
      name: :patches_pr_xref_index, unique: true)
    create index(:projects, [:repo_xref],
      name: :projects_repo_xref_index, unique: true)
    create index(:statuses, [:identifier, :batch_id],
      name: :statuses_identifier_batch_id_index, unique: true)
    create index(:users, [:login],
      name: :users_login_index, unique: true)
    create index(:link_patch_batch, [:patch_id, :batch_id],
      name: :link_patch_batch_patch_id_batch_id_index, unique: true)
    create index(:link_user_project, [:user_id, :project_id],
      name: :link_user_project_user_id_project_id_index, unique: true)
  end
end
