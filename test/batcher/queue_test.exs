defmodule Aelita2.BatcherQueueTest do
  use ExUnit.Case, async: true

  alias Aelita2.Batcher.Queue
  alias Aelita2.Batch

  def bid({_state, batches}) do
    hd(batches).id
  end

  test "splits two waiting items" do
    batch1 = %Batch{project_id: 1, id: 3, state: 0}
    batch2 = %Batch{project_id: 2, id: 4, state: 0}
    batches = Queue.organize_batches_into_project_queues([batch1, batch2])
    |> Enum.sort_by(&bid/1)
    assert batches == [{:waiting, [batch1]}, {:waiting, [batch2]}]
  end

  test "splits chunks" do
    batch1 = %Batch{project_id: 1, id: 3, state: 0, last_polled: 3}
    batch2 = %Batch{project_id: 1, id: 4, state: 0, last_polled: 4}
    batch3 = %Batch{project_id: 2, id: 5, state: 0}
    batches = Queue.organize_batches_into_project_queues([batch1, batch3, batch2])
    |> Enum.sort_by(&bid/1)
    assert batches == [{:waiting, [batch1, batch2]}, {:waiting, [batch3]}]
  end

  test "sorts two waiting items" do
    batch1 = %Batch{project_id: 1, id: 3, state: 0, last_polled: 3}
    batch2 = %Batch{project_id: 1, id: 4, state: 0, last_polled: 4}
    batches = Queue.organize_batches_into_project_queues([batch1, batch2])
    batches2 = Queue.organize_batches_into_project_queues([batch2, batch1])
    expected = [{:waiting, [batch1, batch2]}]
    assert batches == expected
    assert batches2 == expected
  end

  test "sorts a running and waiting item" do
    batch1 = %Batch{project_id: 1, id: 3, state: 0, last_polled: 3}
    batch2 = %Batch{project_id: 1, id: 4, state: 1, last_polled: 4}
    batches = Queue.organize_batches_into_project_queues([batch1, batch2])
    batches2 = Queue.organize_batches_into_project_queues([batch2, batch1])
    expected = [{:running, [batch2, batch1]}]
    assert batches == expected
    assert batches2 == expected
  end

  test "sort chunks" do
    batch1 = %Batch{project_id: 1, id: 3, state: 0, last_polled: 3}
    batch2 = %Batch{project_id: 1, id: 4, state: 1, last_polled: 4}
    batch3 = %Batch{project_id: 2, id: 5, state: 0}
    batches = Queue.organize_batches_into_project_queues([batch1, batch3, batch2])
    |> Enum.sort_by(&bid/1)
    assert batches == [{:running, [batch2, batch1]}, {:waiting, [batch3]}]
  end

  test "empty" do
    assert Queue.organize_batches_into_project_queues([]) == []
  end
end
