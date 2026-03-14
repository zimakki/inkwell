defmodule Inkwell.UpdateChecker do
  @moduledoc "Background checker that caches the latest published Inkwell version."

  use GenServer

  @cache_file "update_check.json"
  @check_interval_seconds 24 * 60 * 60
  @latest_release_url "https://api.github.com/repos/zimakki/inkwell/releases/latest"

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def latest_version(server \\ __MODULE__) do
    if is_pid(server) or Process.whereis(server) do
      GenServer.call(server, :latest_version)
    else
      case cached_info() do
        {:ok, %{latest: latest}} -> latest
        _ -> nil
      end
    end
  end

  def cached_info(opts \\ []) do
    path = cache_path(opts)

    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok,
       %{
         latest: decoded["latest"],
         checked_at: decoded["checked_at"]
       }}
    else
      _ -> :error
    end
  end

  @impl true
  def init(opts) do
    state = %{
      now_fn: Keyword.get(opts, :now_fn, &DateTime.utc_now/0),
      request_fn: Keyword.get(opts, :request_fn, &request_latest_release/0),
      state_dir: Keyword.get(opts, :state_dir, state_dir()),
      latest: nil
    }

    cached =
      case cached_info(state_dir: state.state_dir) do
        {:ok, info} -> info
        :error -> %{latest: nil, checked_at: nil}
      end

    state = %{state | latest: cached.latest}

    if stale?(cached.checked_at, state.now_fn) do
      server = self()

      Task.start(fn ->
        send_check_result(server, state.request_fn, state.state_dir, state.now_fn)
      end)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:latest_version, _from, state) do
    {:reply, state.latest, state}
  end

  @impl true
  def handle_cast({:latest_version_checked, latest}, state) do
    {:noreply, %{state | latest: latest}}
  end

  defp send_check_result(server, request_fn, state_dir, now_fn) do
    latest =
      case request_fn.() do
        {:ok, release} ->
          latest = normalize_version(release["tag_name"])
          write_cache(state_dir, latest, now_fn.())
          latest

        _ ->
          nil
      end

    if latest do
      GenServer.cast(server, {:latest_version_checked, latest})
    end
  end

  defp stale?(nil, _now_fn), do: true

  defp stale?(checked_at, now_fn) do
    with {:ok, checked_at, _offset} <- DateTime.from_iso8601(checked_at) do
      DateTime.diff(now_fn.(), checked_at, :second) >= @check_interval_seconds
    else
      _ -> true
    end
  end

  defp write_cache(state_dir, latest, checked_at) do
    File.mkdir_p!(state_dir)

    payload = %{
      latest: latest,
      checked_at: DateTime.to_iso8601(checked_at)
    }

    File.write!(Path.join(state_dir, @cache_file), Jason.encode!(payload))
  end

  defp request_latest_release do
    case http_get(@latest_release_url, [{"user-agent", "inkwell"} | github_auth_header()]) do
      {:ok, 200, body} -> Jason.decode(body)
      other -> {:error, other}
    end
  end

  defp http_get(url, headers) do
    :inets.start()
    :ssl.start()

    request_headers =
      Enum.map(headers, fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    http_opts = [timeout: 5_000, connect_timeout: 3_000]

    case :httpc.request(
           :get,
           {String.to_charlist(url), request_headers},
           http_opts,
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _resp_headers, body}} -> {:ok, status, body}
      other -> {:error, other}
    end
  end

  defp github_auth_header do
    case System.get_env("GITHUB_TOKEN") do
      nil -> []
      "" -> []
      token -> [{"authorization", "Bearer #{token}"}]
    end
  end

  defp normalize_version("v" <> version), do: version
  defp normalize_version(version), do: version

  defp cache_path(opts) do
    Path.join(Keyword.get(opts, :state_dir, state_dir()), @cache_file)
  end

  defp state_dir do
    Path.join(System.user_home!(), ".inkwell")
  end
end
