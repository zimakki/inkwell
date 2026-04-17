defmodule Inkwell.StaticAssets do
  @moduledoc false

  @asset_names ~w(app.js app.css markdown-wide.css favicon.svg)

  @static_dir Path.join([to_string(:code.priv_dir(:inkwell)), "static"])

  for name <- @asset_names do
    @external_resource Path.join(@static_dir, name)
  end

  @digests (for name <- @asset_names, into: %{} do
              digest =
                @static_dir
                |> Path.join(name)
                |> File.read!()
                |> then(&:crypto.hash(:sha256, &1))
                |> Base.url_encode64(padding: false)
                |> binary_part(0, 12)

              {name, digest}
            end)

  def path(name) do
    "/static/#{name}?vsn=#{Map.fetch!(@digests, name)}"
  end
end
