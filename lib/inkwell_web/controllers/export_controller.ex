defmodule InkwellWeb.ExportController do
  use InkwellWeb, :controller

  def show(conn, params) do
    with {:ok, path} <- fetch_path(params),
         true <- File.regular?(path) || {:error, :not_found},
         true <- pdf_module().available?() || {:error, :chrome_not_found},
         {:ok, pdf} <- generate(path, params) do
      conn
      |> put_resp_header("content-type", "application/pdf")
      |> put_resp_header(
        "content-disposition",
        ~s|attachment; filename="#{Path.basename(path)}.pdf"|
      )
      |> send_resp(200, pdf)
    else
      {:error, :missing_path} -> send_resp(conn, 400, "missing path")
      {:error, :not_absolute} -> send_resp(conn, 400, "path must be absolute")
      {:error, :not_found} -> send_resp(conn, 404, "file not found")
      false -> send_resp(conn, 404, "file not found")
      {:error, :chrome_not_found} -> send_resp(conn, 503, ~s({"error":"chrome_not_found"}))
      {:error, reason} -> send_resp(conn, 500, "pdf generation failed: #{inspect(reason)}")
    end
  end

  defp pdf_module, do: Application.get_env(:inkwell, :pdf_module, Inkwell.Pdf)

  defp fetch_path(%{"path" => path}) when is_binary(path) and byte_size(path) > 0 do
    if String.starts_with?(path, "/"), do: {:ok, path}, else: {:error, :not_absolute}
  end

  defp fetch_path(_), do: {:error, :missing_path}

  defp generate(path, params) do
    print_url = build_print_url(path, params)

    pdf_module().print_url(print_url,
      pagesize: parse_pagesize(params["pagesize"]),
      margins: parse_margins(params["margins"])
    )
  end

  defp build_print_url(path, params) do
    port = Inkwell.Daemon.read_port!()

    forwarded =
      params
      |> Map.take(~w(theme toc numbers pagesize margins))
      |> Map.put("path", path)

    query = URI.encode_query(forwarded)
    "http://127.0.0.1:#{port}/print?#{query}"
  end

  defp parse_pagesize("letter"), do: :letter
  defp parse_pagesize("legal"), do: :legal
  defp parse_pagesize(_), do: :a4

  defp parse_margins("narrow"), do: :narrow
  defp parse_margins("none"), do: :none
  defp parse_margins(_), do: :normal
end
