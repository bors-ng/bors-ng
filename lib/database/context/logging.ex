defmodule BorsNG.Database.Context.Logging do
  @moduledoc """
  Keeps user-accessible records of what happens to their repository.
  """

  use BorsNG.Database.Context

  @spec log_cmd(Patch.t(), User.t(), BorsNG.Command.cmd()) :: :ok
  def log_cmd(patch, user, cmd) do
    %Log{patch: patch, user: user, cmd: cmd}
    |> Repo.insert!()
  end

  @spec most_recent_cmd(Patch.t()) :: {User.t(), BorsNG.Command.cmd()} | nil
  def most_recent_cmd(%Patch{id: id}) do
    from(l in Log)
    |> where([l], l.patch_id == ^id and l.cmd != ^:retry)
    |> order_by([l], desc: l.updated_at, desc: l.id)
    |> preload([l], :user)
    |> limit(1)
    |> Repo.all()
    |> case do
      [%Log{user: user, cmd: cmd}] -> {user, cmd}
      _ -> nil
    end
  end
end
