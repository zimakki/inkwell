defmodule InkwellWeb.RawFileController do
  @moduledoc """
  Serves arbitrary local files referenced by relative image URLs in the rendered
  markdown. The renderer rewrites relative image URLs to `/raw?path=<abs>`; this
  controller reads the file from disk and streams it back with a content-type
  guessed from the extension.

  No path jailing is enforced — Inkwell is a local daemon that already reads
  arbitrary markdown files the user opens, so any file the OS user can read is
  in scope.
  """

  use InkwellWeb, :controller

  def show(conn, params) do
    with {:ok, path} <- fetch_path(params),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path), nil)
      |> send_file(200, path)
    else
      {:error, :missing} -> send_resp(conn, 400, "missing path")
      {:error, :relative} -> send_resp(conn, 400, "path must be absolute")
      false -> send_resp(conn, 404, "Not Found")
    end
  end

  defp fetch_path(%{"path" => path}) when is_binary(path) and byte_size(path) > 0 do
    if Path.type(path) == :absolute do
      {:ok, path}
    else
      {:error, :relative}
    end
  end

  defp fetch_path(_), do: {:error, :missing}
end
