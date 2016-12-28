defmodule Aelita2.BatcherBorsTomlTest do
  use ExUnit.Case, async: true

  test "can parse a single status code" do
    assert Aelita2.Batcher.BorsToml.new("status = [\"exl\"]").status ==
           ["exl"]
  end

  test "can parse two status codes" do
    assert Aelita2.Batcher.BorsToml.new("status = [\"exl\", \"exm\"]").status ==
           ["exl", "exm"]
  end
end
