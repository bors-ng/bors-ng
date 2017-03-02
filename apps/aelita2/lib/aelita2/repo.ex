defmodule Aelita2.Repo do
  @moduledoc """
  An ecto data repository;
  this process interacts with your persistent database.

  Do not confuse this with a GitHub repo.
  We call those Projects internally.
  """

  use Ecto.Repo, otp_app: :aelita2
end
