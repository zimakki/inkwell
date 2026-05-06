defmodule Inkwell.Pdf do
  @moduledoc """
  ChromicPDF wrapper. Auto-detects Chrome at boot, lazy-starts the ChromicPDF
  supervisor on first export, exposes a small `available?/0` + `print_url/2`
  surface for callers (`InkwellWeb.ExportController`).
  """

  @persistent_key :inkwell_chrome_available

  @doc """
  Probe for an installed Chrome/Chromium executable. Caches the result in
  `:persistent_term` under #{inspect(@persistent_key)}. Returns `{:ok, path}`
  on success, `:error` otherwise.
  """
  @spec detect_chrome() :: {:ok, String.t()} | :error
  def detect_chrome do
    value =
      env_var_path()
      |> first_existing()
      |> case do
        nil -> :error
        path -> {:ok, path}
      end

    :persistent_term.put(@persistent_key, value)

    value
  end

  defp env_var_path do
    case System.get_env("INKWELL_CHROME_PATH") do
      nil -> []
      "" -> []
      path -> [path]
    end
  end

  defp first_existing(paths) do
    Enum.find(paths, fn path ->
      File.exists?(path) and not File.dir?(path)
    end)
  end
end
