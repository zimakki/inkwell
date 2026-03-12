defmodule Inkwell do
  @moduledoc false

  def preview_url(path) do
    path = Path.expand(path)
    port = Inkwell.Daemon.read_port!()
    "http://localhost:#{port}/?path=#{URI.encode_www_form(path)}"
  end

  def open_file(path, opts \\ []) do
    path = Path.expand(path)
    theme = Keyword.get(opts, :theme)

    Inkwell.Watcher.ensure_file(path)
    Inkwell.History.push(path)

    if theme do
      :persistent_term.put(:inkwell_theme, theme)
    end

    %{url: preview_url(path), path: path, theme: :persistent_term.get(:inkwell_theme, "dark")}
  end
end
