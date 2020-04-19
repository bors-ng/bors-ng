defmodule BorsNG.LayoutView do
  @moduledoc """
  The common wrapper for all pages; namely,
  the bar along the top and the disclaimer along the bottom.
  """

  use BorsNG.Web, :view

  def get_version do
    get_commit() || get_tag()
  end

  def get_commit do
    hash = get_heroku_commit() || get_git_commit()

    if hash do
      {String.slice(hash, 0..6), hash}
    else
      nil
    end
  end

  def get_tag do
    v = get_release_version()
    {v, "v#{v}"}
  end

  def get_heroku_commit do
    System.get_env("HEROKU_SLUG_COMMIT")
  end

  def get_git_commit do
    ".git/HEAD"
    |> File.read()
    |> case do
      {:ok, "ref: " <> branch} ->
        branch = String.trim(branch)

        case File.read(".git/" <> branch) do
          {:ok, commit} -> String.trim(commit)
          _ -> nil
        end

      {:ok, commit} ->
        String.trim(commit)

      _ ->
        nil
    end
  end

  def get_release_version do
    case :application.get_key(:vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> nil
    end
  end

  def get_header_html do
    Confex.fetch_env!(:bors, BorsNG)[:dashboard_header_html]
  end

  def get_footer_html do
    Confex.fetch_env!(:bors, BorsNG)[:dashboard_footer_html]
  end
end
