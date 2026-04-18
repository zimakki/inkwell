defmodule InkwellWeb.FileDialogController do
  @moduledoc "Native macOS file/folder picker endpoints. Backing module is configurable for tests via :file_dialog_module."

  use InkwellWeb, :controller

  def file(conn, _params) do
    case dialog_module().pick_file() do
      {:ok, path} ->
        json(conn, %{path: path, filename: Path.basename(path)})

      :cancel ->
        send_resp(conn, 204, "")

      {:error, reason} ->
        send_resp(conn, 500, to_string(reason))
    end
  end

  def directory(conn, _params) do
    case dialog_module().pick_directory() do
      {:ok, dir} ->
        json(conn, %{dir: dir})

      :cancel ->
        send_resp(conn, 204, "")

      {:error, reason} ->
        send_resp(conn, 500, to_string(reason))
    end
  end

  defp dialog_module do
    Application.get_env(:inkwell, :file_dialog_module, Inkwell.FileDialog)
  end
end
