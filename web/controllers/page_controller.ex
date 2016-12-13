defmodule Aelita2.PageController do
  use Aelita2.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
