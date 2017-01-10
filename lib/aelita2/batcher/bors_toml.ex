defmodule Aelita2.Batcher.BorsToml do
  @moduledoc """
  The format for `bors.toml`. It looks like this:

      status = [
        "continuous-integration/travis-ci/push",
        "continuous-integration/appveyor/branch"]
  """

  defstruct status: [""]

  def new(str) when is_binary(str) do
    case :etoml.parse(str) do
      {:ok, toml} ->
        toml = Map.new(toml)
        {:ok, %Aelita2.Batcher.BorsToml{
          status: toml["status"]
        }}
      {:error, _error} -> {:err, :parse_failed}
    end
  end

end
