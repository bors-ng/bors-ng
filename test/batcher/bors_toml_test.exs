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

  test "default to no status codes" do
    {:ok, toml} = Aelita2.Batcher.BorsToml.new(~s//)
    assert toml.status == []
  end

  test "has a default timeout" do
    {:ok, toml} = Aelita2.Batcher.BorsToml.new(~s/status = ["exl"]/)
    assert is_integer toml.timeout_sec
  end

  test "can parse a custom timeout" do
    {:ok, toml} = Aelita2.Batcher.BorsToml.new(
      ~s/status = ["exl"]\ntimeout_sec = 1/)
    assert toml.timeout_sec == 1
  end

  test "recognizes a parse failure" do
    r = Aelita2.Batcher.BorsToml.new(~s/status = "/)
    assert r == {:error, :parse_failed}
  end

  test "recognizes an invalid timeout" do
    r = Aelita2.Batcher.BorsToml.new(~s/status = []\ntimeout_sec = "3 days"/)
    assert r == {:error, :timeout_sec}
  end

  test "recognizes an invalid status" do
    r = Aelita2.Batcher.BorsToml.new(~s/status = "exl"/)
    assert r == {:error, :status}
  end
end
