defmodule BorsNG.ServerControllerTest do
  use BorsNG.ConnCase

  test "health endpoint should return 200 status code", %{conn: conn} do
    conn = get(conn, "/health")
    assert conn.status == 200
  end
end
