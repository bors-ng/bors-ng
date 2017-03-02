defmodule BorsNG.Batcher.Queue do
  @moduledoc """
  Queries that turn an ecto repo into a queue.
  """

  def organize_batches_into_project_queues(batches) do
    batches
    |> Enum.reduce(%{}, &add_batch_to_project_map/2)
    |> Enum.map(&sort_batches/1)
  end

  defp add_batch_to_project_map(batch, project_map) do
    project_id = batch.project_id
    {_, map} = Map.get_and_update(
      project_map,
      project_id,
      &prepend_or_new(&1, batch))
    map
  end

  # This wouldn't be a bad idea for the standard library.
  defp prepend_or_new(list, item) do
    new = if is_nil(list) do
      [item]
    else
      [item | list]
    end
    {item, new}
  end

  defp sort_batches({_project_id, batches}) do
    sorted_batches = Enum.sort_by(batches, &{-&1.state, &1.last_polled})
    new_batches = Enum.dedup_by(sorted_batches, &(&1.id))
    state = if new_batches != [] and hd(new_batches).state == 1 do
      :running
    else
      Enum.each(new_batches, fn batch -> 0 = batch.state end)
      :waiting
    end
    {state, new_batches}
  end
end
