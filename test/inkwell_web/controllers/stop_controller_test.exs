defmodule InkwellWeb.StopControllerTest do
  use InkwellWeb.ConnCase, async: false

  test "POST /stop returns 200", %{conn: conn} do
    conn = post(conn, ~p"/stop")
    assert response(conn, 200) == "Stopping"
  end
end
