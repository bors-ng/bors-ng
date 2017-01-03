defmodule Aelita2.Batcher.Message do
  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]
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
  def send(token, patches, message) do
    body = generate_message(message)
    Enum.each(patches, &@github_api.post_comment!(token, &1.project.repo_xref, &1.pr_xref, body))
  end
end
