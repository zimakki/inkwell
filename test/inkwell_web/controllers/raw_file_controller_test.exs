defmodule InkwellWeb.RawFileControllerTest do
  use InkwellWeb.ConnCase, async: true

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "raw_file_controller_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  describe "GET /raw" do
    test "serves an existing file with a content-type derived from the extension",
         %{conn: conn, tmp: tmp} do
      png_path = Path.join(tmp, "pic.png")
      png_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>
      File.write!(png_path, png_bytes)

      conn = get(conn, ~p"/raw?path=#{png_path}")

      assert response(conn, 200) == png_bytes
      assert get_resp_header(conn, "content-type") == ["image/png"]
    end

    test "returns 404 when the file does not exist", %{conn: conn, tmp: tmp} do
      missing = Path.join(tmp, "nope.png")

      conn = get(conn, ~p"/raw?path=#{missing}")

      assert response(conn, 404)
    end

    test "returns 400 when the path param is missing", %{conn: conn} do
      conn = get(conn, ~p"/raw")
      assert response(conn, 400)
    end

    test "returns 400 when the path is not absolute", %{conn: conn} do
      conn = get(conn, ~p"/raw?path=relative/pic.png")
      assert response(conn, 400)
    end

    test "returns 404 for a directory even if it exists", %{conn: conn, tmp: tmp} do
      conn = get(conn, ~p"/raw?path=#{tmp}")
      assert response(conn, 404)
    end
  end
end
