defmodule InkwellWeb.FileDialogControllerTest do
  use InkwellWeb.ConnCase, async: true

  defmodule Stub do
    def pick_file, do: Process.get(:pick_file_result)
    def pick_directory, do: Process.get(:pick_directory_result)
  end

  setup do
    # Each test process gets its own stub return values via the process dict.
    :ok
  end

  describe "GET /pick-file" do
    test "returns path and filename when user selects a file", %{conn: conn} do
      Process.put(:pick_file_result, {:ok, "/tmp/foo.md"})
      conn = get(conn, ~p"/pick-file")
      body = json_response(conn, 200)
      assert body["path"] == "/tmp/foo.md"
      assert body["filename"] == "foo.md"
    end

    test "returns 204 when user cancels", %{conn: conn} do
      Process.put(:pick_file_result, :cancel)
      conn = get(conn, ~p"/pick-file")
      assert response(conn, 204) == ""
    end

    test "returns 500 with reason on error", %{conn: conn} do
      Process.put(:pick_file_result, {:error, "boom"})
      conn = get(conn, ~p"/pick-file")
      assert response(conn, 500) == "boom"
    end
  end

  describe "GET /pick-directory" do
    test "returns dir when user selects a folder", %{conn: conn} do
      Process.put(:pick_directory_result, {:ok, "/tmp/docs"})
      conn = get(conn, ~p"/pick-directory")
      body = json_response(conn, 200)
      assert body["dir"] == "/tmp/docs"
    end

    test "returns 204 when user cancels", %{conn: conn} do
      Process.put(:pick_directory_result, :cancel)
      conn = get(conn, ~p"/pick-directory")
      assert response(conn, 204) == ""
    end

    test "returns 500 with reason on error", %{conn: conn} do
      Process.put(:pick_directory_result, {:error, "boom"})
      conn = get(conn, ~p"/pick-directory")
      assert response(conn, 500) == "boom"
    end
  end
end
