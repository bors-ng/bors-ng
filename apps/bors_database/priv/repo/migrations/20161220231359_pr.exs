defmodule BorsNG.Repo.Migrations.Pr do
  use Ecto.Migration

  def change do
    create table(:batches) do
      add :project_id, references(:projects, on_delete: :delete_all)
      add :commit, :varchar, size: 40
      add :state, :integer
      add :last_polled, :integer
      timestamps()
    end
    create table(:patches) do
      add :project_id, references(:projects, on_delete: :delete_all)
      add :pr_xref, :integer
      add :title, :text
      add :body, :text
      add :commit, :text
      add :author_id, references(:users, on_delete: :nilify_all)
      timestamps()
    end
    create table(:statuses) do
      add :identifier, :string
      add :url, :string
      add :state, :integer
      timestamps()
    end
    alter table(:projects) do
      add :master_branch, :string, default: "master"
      add :staging_branch, :string, default: "staging"
      add :batch_poll_period_sec, :integer, default: (60 * 30)
      add :batch_delay_sec, :integer, default: 10
      add :batch_timeout_sec, :integer, default: (60 * 60 * 2)
    end
  end
end
