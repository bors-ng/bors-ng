defmodule BorsNG.Database.RepoPostgres.Migrations.HookSecretsAndPhase do
  use Ecto.Migration

  defp fetch_adapter do
    repo_module =
      case System.get_env("BORS_DATABASE", "postgresql") do
        "mysql" -> BorsNG.Database.RepoMysql
        _ -> BorsNG.Database.RepoPostgres
      end

    Confex.fetch_env!(:bors, repo_module)[:adapter]
  end

  def up do
    length = div(256, 8)
    alter table(:hooks) do
      add :phase, :integer
      add :comment, :string
    end
    alter table(:projects) do
      add :hook_secret, :binary
    end
    # eh...
    case fetch_adapter() do
      Ecto.Adapters.Postgres ->
        execute "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
        execute """
          UPDATE projects
          SET hook_secret = gen_random_bytes(#{length});
        """
      Ecto.Adapters.MyXQL ->
        # Note: I have not tested this!
        execute """
          UPDATE projects
          SET hook_secret = RANDOM_BYTES(#{length});
        """
    end
  end
  def down do
    alter table(:hooks) do
      remove :phase, :integer
      remove :comment, :string
    end
    alter table(:projects) do
      remove :hook_secret, :binary
    end
    # eh...
    # TODO: this only works on postgresql, not mysql or whatever
    case fetch_adapter() do
      Ecto.Adapters.Postgres ->
        execute """
          DROP EXTENSION pgcrypto;
        """
      Ecto.Adapters.MyXQL ->
        :ok
    end
  end
end
