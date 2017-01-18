defmodule Aelita2.Batcher.BorsToml do
  @moduledoc """
  The format for `bors.toml`. It looks like this:

      status = [
        "continuous-integration/travis-ci/push",
        "continuous-integration/appveyor/branch"]
  """

  defstruct status: [""], timeout_sec: (60 * 60)

  def new(str) when is_binary(str) do
    case :etoml.parse(str) do
      {:ok, toml} ->
        toml = Map.new(toml)
        toml = %Aelita2.Batcher.BorsToml{
          status: Map.get(toml, "status", []),
          timeout_sec: Map.get(toml, "timeout_sec", 60 * 60)}
        case toml do
          %{status: status} when not is_list status ->
            {:error, :status}
          %{timeout_sec: timeout_sec} when not is_integer timeout_sec ->
            {:error, :timeout_sec}
          toml -> {:ok, toml}
        end
      {:error, _error} -> {:error, :parse_failed}
    end
  end

end
