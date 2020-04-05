defmodule BorsNG.Attrs do
  @moduledoc """
  Storage for different runtime constants, basically config evaled in runtime
  """

  alias BorsNG.GitHub
  alias BorsNG.Attrs

  def start_link do
    pid = Agent.start_link(fn -> %{} end, name: __MODULE__)
    Attrs.set_github_app_public_link(GitHub.get_app!())
    pid
  end

  @spec get_github_integration_url :: String.t()
  def get_github_integration_url do
    link =
      Agent.get(__MODULE__, &Map.get(&1, :github_app_public_link)) ||
        "#{Confex.fetch_env!(:bors, :html_github_root)}/apps/bors"

    "#{link}/installations/new"
  end

  @spec set_github_app_public_link(binary) :: :ok
  def set_github_app_public_link(link) do
    Agent.update(__MODULE__, &Map.put(&1, :github_app_public_link, link))
  end
end
