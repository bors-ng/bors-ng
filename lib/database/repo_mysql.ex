defmodule BorsNG.Database.RepoMysql do
  @moduledoc """
  An ecto data repository;
  this process interacts with your persistent database.

  Do not confuse this with a GitHub repo.
  We call those `Project`s internally.
  """

  use Ecto.Repo,
    otp_app: :bors,
    adapter: Ecto.Adapters.MyXQL

  def init(_, config) do
    config = Confex.Resolver.resolve!(config)

    {:ok, config}
  end
end
