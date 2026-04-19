defmodule InkwellWeb.StopController do
  use InkwellWeb, :controller

  def stop(conn, _params) do
    conn = send_resp(conn, 200, "Stopping")

    if Application.get_env(:inkwell, :shutdown_on_stop, true) do
      spawn(fn ->
        Process.sleep(100)
        System.stop(0)
      end)
    end

    conn
  end
end
