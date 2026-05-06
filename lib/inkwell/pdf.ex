defmodule Inkwell.Pdf do
  @moduledoc """
  ChromicPDF wrapper. Auto-detects Chrome at boot, lazy-starts the ChromicPDF
  supervisor on first export, exposes a small `available?/0` + `print_url/2`
  surface for callers (`InkwellWeb.ExportController`).
  """

  @persistent_key :inkwell_chrome_available

  @macos_paths [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  ]

  @linux_paths [
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium"
  ]

  @windows_paths [
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"
  ]

  @path_lookups [~c"google-chrome", ~c"chromium", ~c"chrome"]

  @doc """
  Returns true when a Chrome/Chromium executable was detected at boot.
  Pure persistent_term lookup; safe to call from hot paths.
  """
  @spec available?() :: boolean
  def available? do
    case :persistent_term.get(@persistent_key, :error) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Probe for an installed Chrome/Chromium executable. Caches the result in
  `:persistent_term` under #{inspect(@persistent_key)}. Returns `{:ok, path}`
  on success, `:error` otherwise.
  """
  @spec detect_chrome() :: {:ok, String.t()} | :error
  def detect_chrome do
    value =
      (env_var_path() ++
         @macos_paths ++
         @linux_paths ++
         @windows_paths ++
         path_lookup_results())
      |> first_existing()
      |> case do
        nil -> :error
        path -> {:ok, path}
      end

    :persistent_term.put(@persistent_key, value)
    value
  end

  defp path_lookup_results do
    Enum.flat_map(@path_lookups, fn name ->
      case :os.find_executable(name) do
        false -> []
        path -> [List.to_string(path)]
      end
    end)
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
