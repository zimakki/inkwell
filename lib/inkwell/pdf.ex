defmodule Inkwell.Pdf do
  @moduledoc """
  ChromicPDF wrapper. Auto-detects Chrome at boot, lazy-starts the ChromicPDF
  supervisor on first export, exposes a small `available?/0` + `print_url/2`
  surface for callers (`InkwellWeb.ExportController`).
  """

  @behaviour __MODULE__

  @callback available?() :: boolean
  @callback print_url(String.t(), keyword) :: {:ok, binary} | {:error, term}

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
  @impl true
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

  @doc """
  Render a remote URL to PDF via ChromicPDF, lazy-starting the ChromicPDF
  supervisor on first call. Returns `{:ok, binary}` on success.

  `opts` keys:
    * `:pagesize` — `:a4` / `:letter` / `:legal` (default `:a4`)
    * `:margins`  — `:normal` / `:narrow` / `:none` (default `:normal`)
  """
  @impl true
  @spec print_url(String.t(), keyword) :: {:ok, binary} | {:error, term}
  def print_url(url, opts \\ []) do
    with :ok <- ensure_started() do
      pagesize = Keyword.get(opts, :pagesize, :a4)
      margins = Keyword.get(opts, :margins, :normal)

      ChromicPDF.print_to_pdf(
        {:url, url},
        print_to_pdf: %{
          paperWidth: paper_width_inches(pagesize),
          paperHeight: paper_height_inches(pagesize),
          marginTop: margin_inches(margins),
          marginBottom: margin_inches(margins),
          marginLeft: margin_inches(margins),
          marginRight: margin_inches(margins),
          printBackground: true,
          preferCSSPageSize: true
        },
        output: &File.read!/1
      )
    end
  end

  defp ensure_started do
    case :persistent_term.get(@persistent_key, :error) do
      {:ok, chrome_path} ->
        case Process.whereis(ChromicPDF) do
          nil -> start_chromic(chrome_path)
          _ -> :ok
        end

      :error ->
        {:error, :chrome_unavailable}
    end
  end

  defp start_chromic(chrome_path) do
    # ChromicPDF defaults init_timeout/timeout to 5_000ms, which is too short
    # for a cold Chrome warming up on a 30+ page document — the workers all
    # time out at init and the pool wedges. We bump generously since this is
    # a local desktop daemon, not a high-throughput service.
    config = [
      chrome_executable: chrome_path,
      session_pool: [init_timeout: 30_000, timeout: 60_000]
    ]

    case ChromicPDF.start_link(config) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, {:chromic_start_failed, reason}}
    end
  end

  defp paper_width_inches(:a4), do: 8.27
  defp paper_width_inches(:letter), do: 8.5
  defp paper_width_inches(:legal), do: 8.5

  defp paper_height_inches(:a4), do: 11.69
  defp paper_height_inches(:letter), do: 11.0
  defp paper_height_inches(:legal), do: 14.0

  defp margin_inches(:normal), do: 1.0
  defp margin_inches(:narrow), do: 0.5
  defp margin_inches(:none), do: 0.0
end
