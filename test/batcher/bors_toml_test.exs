defmodule Aelita2.BatcherBorsTomlTest do
  use ExUnit.Case, async: true

  test "can parse a single status code" do
    {:ok, toml} = Aelita2.Batcher.BorsToml.new(~s/status = ["exl"]/)
    assert toml.status == ["exl"]
  end

  test "can parse two status codes" do
    {:ok, toml} = Aelita2.Batcher.BorsToml.new(~s/status = ["exl", "exm"]/)
    assert toml.status == ["exl", "exm"]
  end
end
