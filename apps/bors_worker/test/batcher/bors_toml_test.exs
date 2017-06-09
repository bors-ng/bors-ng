defmodule BatcherBorsTomlTest do
  use ExUnit.Case, async: true

  alias BorsNG.Worker.Batcher.BorsToml

  test "does not accept an empty config file" do
    r = BorsToml.new("")
    assert r == {:error, :empty_config}
  end

  test "accepts a config file with just labels" do
    {:ok, toml} = BorsToml.new(~s/block_labels = ["l1"]/)
    assert toml == %BorsToml{
      pr_status: [],
      status: [],
      block_labels: ["l1"],
      timeout_sec: 3600}
  end

  test "can parse a single status code" do
    {:ok, toml} = BorsToml.new(~s/status = ["exl"]/)
    assert toml.status == ["exl"]
  end

  test "can parse two status codes" do
    {:ok, toml} = BorsToml.new(~s/status = ["exl", "exm"]/)
    assert toml.status == ["exl", "exm"]
  end

  test "has a default timeout" do
    {:ok, toml} = BorsToml.new(~s/status = ["exl"]/)
    assert is_integer toml.timeout_sec
  end

  test "can parse a custom timeout" do
    {:ok, toml} = BorsToml.new(
      ~s/status = ["exl"]\ntimeout_sec = 1/)
    assert toml.timeout_sec == 1
  end

  test "can parse a custom timeout with hyphen" do
    {:ok, toml} = BorsToml.new(
      ~s/status = ["exl"]\ntimeout-sec = 2/)
    assert toml.timeout_sec == 2
  end

  test "defaults cut_body_after to nil" do
    {:ok, toml} = BorsToml.new(~s/status = ["exl"]/)
    assert is_nil toml.cut_body_after
  end

  test "recognizes a parse failure" do
    r = BorsToml.new(~s/status = "/)
    assert r == {:error, :parse_failed}
  end

  test "recognizes an invalid timeout" do
    r = BorsToml.new(~s/status = []\ntimeout_sec = "3 days"/)
    assert r == {:error, :timeout_sec}
  end

  test "recognizes an invalid status" do
    r = BorsToml.new(~s/status = "exl"/)
    assert r == {:error, :status}
  end

  test "recognizes an invalid cut_body_after" do
    r = BorsToml.new(~s/cut_body_after = 13/)
    assert r == {:error, :cut_body_after}
  end
end
