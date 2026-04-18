defmodule InkwellWeb.HealthController do
  use InkwellWeb, :controller

  def show(conn, _params) do
    version = Application.spec(:inkwell, :vsn) |> to_string()
    json(conn, %{ok: true, version: version})
  end

  def status(conn, _params) do
    json(conn, Inkwell.Daemon.status_info())
  end
end
