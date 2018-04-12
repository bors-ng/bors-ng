defmodule BorsNG.Database.Context.Logging do
  @moduledoc """
  Keeps user-accessible records of what happens to their repository.
  """

  use BorsNG.Database.Context

  @spec log_cmd(Patch.t, User.t, BorsNG.Command.cmd) :: :ok
  def log_cmd(patch, user, cmd) do
    %Log{patch: patch, user: user, cmd: cmd}
    |> Repo.insert!()
  end
end
