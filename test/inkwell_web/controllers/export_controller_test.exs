defmodule InkwellWeb.ExportControllerTest do
  use InkwellWeb.ConnCase, async: false

  defmodule StubPdf do
    @behaviour Inkwell.Pdf

    @impl true
    def available?, do: Process.get(:stub_available?, true)

    @impl true
    def print_url(_url, _opts), do: Process.get(:stub_print_url, {:ok, "%PDF-1.4 stub bytes"})
  end

  setup_all do
    File.mkdir_p!(Path.join(System.user_home!(), ".inkwell"))
    File.write!(Path.join(System.user_home!(), ".inkwell/port"), "4000")
    :ok
  end

  setup do
    Application.put_env(:inkwell, :pdf_module, StubPdf)
    on_exit(fn -> Application.put_env(:inkwell, :pdf_module, Inkwell.Pdf) end)

    tmp =
      Path.join(
        System.tmp_dir!(),
        "export_controller_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  describe "GET /export.pdf" do
    test "streams the PDF binary with attachment headers", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hi\n")

      conn = get(conn, ~p"/export.pdf?path=#{md}")

      assert response(conn, 200) == "%PDF-1.4 stub bytes"
      assert get_resp_header(conn, "content-type") == ["application/pdf"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s|attachment; filename="doc.md.pdf"|
             ]
    end

    test "returns 503 when Pdf.available?/0 is false", %{conn: conn, tmp: tmp} do
      Process.put(:stub_available?, false)

      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hi\n")

      conn = get(conn, ~p"/export.pdf?path=#{md}")
      assert response(conn, 503) =~ "chrome_not_found"
    end

    test "returns 404 when the file does not exist", %{conn: conn, tmp: tmp} do
      missing = Path.join(tmp, "nope.md")
      conn = get(conn, ~p"/export.pdf?path=#{missing}")
      assert response(conn, 404)
    end

    test "returns 500 with a clear message when print_url returns an error",
         %{conn: conn, tmp: tmp} do
      Process.put(:stub_print_url, {:error, :chrome_unavailable})

      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hi\n")

      conn = get(conn, ~p"/export.pdf?path=#{md}")
      assert response(conn, 500) =~ "chrome_unavailable"
    end
  end
end
