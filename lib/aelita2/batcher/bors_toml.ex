defmodule Aelita2.Batcher.BorsToml do
  defstruct status: [""]

  def new(str) when is_binary(str) do
    case :etoml.parse(str) do
      {:ok, toml} ->
        toml = Map.new(toml)
        %Aelita2.Batcher.BorsToml{
          status: toml["status"]
        }
      {:error, _error} -> {:err, :parse_failed}
    end
  end

end
