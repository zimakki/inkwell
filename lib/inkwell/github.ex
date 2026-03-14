defmodule Inkwell.GitHub do
  @moduledoc false

  def http_get(url, headers) do
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

  def download_binary(url, headers) do
    :inets.start()
    :ssl.start()

    request_headers =
      Enum.map(headers, fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    http_opts = [timeout: 30_000, connect_timeout: 5_000]

    case :httpc.request(
           :get,
           {String.to_charlist(url), request_headers},
           http_opts,
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _resp_headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _resp_headers, body}} -> {:error, {:http_error, status, body}}
      other -> {:error, other}
    end
  end

  def request_headers do
    [{"user-agent", "inkwell"} | auth_header()]
  end

  def auth_header do
    case System.get_env("GITHUB_TOKEN") do
      nil -> []
      "" -> []
      token -> [{"authorization", "Bearer #{token}"}]
    end
  end

  def normalize_version("v" <> version), do: version
  def normalize_version(version), do: version
end
