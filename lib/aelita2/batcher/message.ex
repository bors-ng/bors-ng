defmodule Aelita2.Batcher.Message do
  @moduledoc """
  User-readable strings that go in commit messages and comments.
  """

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
    Enum.reduce(statuses, "# #{msg}", &gen_status_link/2)
  end
  defp gen_status_link(status, acc) do
    status_link = case status.url do
      nil -> status.identifier
      url -> "[#{status.identifier}](#{url})"
    end
    "#{acc}\n  * #{status_link}"
  end

  def generate_commit_message(patches) do
    patches = Enum.sort_by(patches, &(&1.pr_xref))
    commit_title = Enum.reduce(patches, "Merge", &"#{&2} \##{&1.pr_xref}")
    commit_body = Enum.reduce(patches, "", &"#{&2}#{&1.pr_xref}: #{&1.title}\n")
    "#{commit_title}\n\n#{commit_body}"
  end
end
