defmodule Inkwell.StaticAssets do
  @moduledoc false

  def path(name) do
    "/static/#{name}?vsn=#{digest(name)}"
  end

  defp digest(name) do
    name
    |> asset_file()
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp asset_file(name) do
    :inkwell
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("static")
    |> Path.join(name)
  end
end
