defmodule BorsNG.Database.Log.Cmd do
  @moduledoc """
  An already-parsed bors command. Represented as a binary Erlang term.
  """
  def type, do: :binary
  def load(any), do: cast(any)

  def cast(binary = <<131, _::binary>>) do
    {:ok, :erlang.binary_to_term(binary)}
  end

  def cast(any), do: {:ok, any}

  def dump(any) do
    {:ok, :erlang.term_to_binary(any)}
  end
end

defmodule BorsNG.Database.Log do
  @moduledoc """
  Detailed command log of every patch.
  """

  use BorsNG.Database.Model

  @type t :: %Log{}

  schema "log" do
    belongs_to(:patch, Patch)
    belongs_to(:user, User)
    field(:cmd, Log.Cmd)
    timestamps()
  end
end
