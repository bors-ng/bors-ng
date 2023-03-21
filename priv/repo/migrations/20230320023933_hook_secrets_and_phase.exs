defmodule BorsNG.Database.RepoPostgres.Migrations.HookSecretsAndPhase do
  use Ecto.Migration

  def change do
    alter table(:hooks) do
      add :phase, :integer
    end
    alter table(:projects) do
      add :hook_secret, :binary
    end
    # eh...
    # TODO: this only works on postgresql, not mysql or whatever
    execute """
      CREATE EXTENSION IF NOT EXISTS pgcrypto;
    """
    execute """
      UPDATE projects
      SET hook_secret = gen_random_bytes(256 / 8);
    """
  end
end
