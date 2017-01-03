defmodule Aelita2.Batcher.Message do
  def generate_message({:config, message}) do
    "# Configuration problem\n#{message}"
  end
  def generate_message({:conflict, :failed}) do
    "# Merge conflict"
  end
  def generate_message({:conflict, :retrying}) do
    "# Merge conflict (retrying...)"
  end
  def generate_message({state, statuses}) do
    msg = case state do
      :succeeded -> "Build succeeded"
      :failed -> "Build failed"
      :retrying -> "Build failed (retrying...)"
    end
    body = Enum.reduce(statuses, "# #{msg}", &gen_status_link/2)
  end
  defp gen_status_link(status, acc) do
    status_link = case status.url do
      nil -> status.identifier
      url -> "[#{status.identifier}](#{url})"
    end
    "#{acc}\n  * #{status_link}"
  end
end
