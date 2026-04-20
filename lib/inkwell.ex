defmodule Inkwell do
  @moduledoc """
  Public API for the Inkwell live markdown preview daemon.
  """

  @doc "Returns the browser URL for previewing the given markdown file."
  def preview_url(path) do
    path = Path.expand(path)
    port = Inkwell.Daemon.read_port!()
    "http://localhost:#{port}/?path=#{URI.encode_www_form(path)}"
  end

  @doc "Opens a file for preview, registers it with the watcher, and returns metadata."
  def open_file(path, opts \\ []) do
    path = Path.expand(path)
    theme = Keyword.get(opts, :theme)

    Inkwell.Watcher.ensure_file(path)
    Inkwell.Library.push_recent!(path)

    if theme do
      :persistent_term.put(:inkwell_theme, theme)
    end

    %{url: preview_url(path), path: path, theme: :persistent_term.get(:inkwell_theme, "dark")}
  end
end
