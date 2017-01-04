defmodule Aelita2.BatcherStateTest do
  use ExUnit.Case, async: true

  alias Aelita2.Batcher.State

  test "summarize" do
    assert State.summarize(:waiting, :waiting) == :waiting
    assert State.summarize(:waiting, :running) == :waiting
    assert State.summarize(:waiting, :ok) == :waiting
    assert State.summarize(:waiting, :err) == :err
    assert State.summarize(:running, :waiting) == :waiting
    assert State.summarize(:running, :running) == :running
    assert State.summarize(:running, :ok) == :running
    assert State.summarize(:running, :err) == :err
    assert State.summarize(:ok, :waiting) == :waiting
    assert State.summarize(:ok, :running) == :running
    assert State.summarize(:ok, :ok) == :ok
    assert State.summarize(:ok, :err) == :err
    assert State.summarize(:err, :waiting) == :err
    assert State.summarize(:err, :running) == :err
    assert State.summarize(:err, :ok) == :err
    assert State.summarize(:err, :err) == :err
  end

  test "summary containing an err is err" do
    assert State.summary_states([:ok, :running, :err]) == :err
    assert State.summary_states([:ok, :err]) == :err
    assert State.summary_states([:err]) == :err
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
