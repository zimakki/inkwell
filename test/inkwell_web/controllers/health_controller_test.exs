defmodule InkwellWeb.HealthControllerTest do
  use InkwellWeb.ConnCase, async: true

  test "GET /health returns ok + version", %{conn: conn} do
    conn = get(conn, ~p"/health")
    body = json_response(conn, 200)
    assert body["ok"] == true
    assert is_binary(body["version"])
    assert body["version"] == to_string(Application.spec(:inkwell, :vsn))
  end

  test "GET /status returns daemon status", %{conn: conn} do
    conn = get(conn, ~p"/status")
    body = json_response(conn, 200)
    assert body["running"] == true
    assert is_binary(body["pid"])
  end
end
