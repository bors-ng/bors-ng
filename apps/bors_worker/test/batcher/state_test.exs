defmodule BorsNG.Worker.BatcherStateTest do
  use ExUnit.Case, async: true

  alias BorsNG.Worker.Batcher.State

  test "summarize" do
    assert State.summarize(:waiting, :waiting) == :waiting
    assert State.summarize(:waiting, :running) == :waiting
    assert State.summarize(:waiting, :ok) == :waiting
    assert State.summarize(:waiting, :error) == :error
    assert State.summarize(:running, :waiting) == :waiting
    assert State.summarize(:running, :running) == :running
    assert State.summarize(:running, :ok) == :running
    assert State.summarize(:running, :error) == :error
    assert State.summarize(:ok, :waiting) == :waiting
    assert State.summarize(:ok, :running) == :running
    assert State.summarize(:ok, :ok) == :ok
    assert State.summarize(:ok, :error) == :error
    assert State.summarize(:error, :waiting) == :error
    assert State.summarize(:error, :running) == :error
    assert State.summarize(:error, :ok) == :error
    assert State.summarize(:error, :error) == :error
  end

  test "summary containing an err is err" do
    assert State.summary_states([:ok, :running, :error]) == :error
    assert State.summary_states([:ok, :error]) == :error
    assert State.summary_states([:error]) == :error
  end

  test "summary of ok is ok" do
    assert State.summary_states([]) == :ok
    assert State.summary_states([:ok]) == :ok
    assert State.summary_states([:ok, :ok]) == :ok
  end

  test "summary of ok and running is running" do
    assert State.summary_states([:ok, :running]) == :running
    assert State.summary_states([:running, :ok]) == :running
  end
end
