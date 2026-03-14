defmodule Inkwell.Updater do
  @moduledoc "Checks for and applies CLI self-updates from GitHub releases."

  @latest_release_url "https://api.github.com/repos/zimakki/inkwell/releases/latest"
  @homebrew_prefixes [
    "/opt/homebrew/",
    "/usr/local/Cellar/",
    "/home/linuxbrew/",
    "/home/linuxbrew/.linuxbrew/"
  ]

  def check(opts \\ []) do
    with {:ok, release} <- fetch_release(opts),
         {:ok, latest} <- release_version(release) do
      current = Keyword.get(opts, :current_version, current_version())
      method = install_method(Keyword.get(opts, :executable_path, current_executable!()))

      case Version.compare(latest, current) do
        :gt -> {:update_available, %{current: current, latest: latest, install_method: method}}
        _ -> {:up_to_date, %{current: current, latest: latest, install_method: method}}
      end
    end
  end

  def update(opts \\ []) do
    executable_path = Keyword.get(opts, :executable_path, current_executable!())

    case install_method(executable_path) do
      :homebrew ->
        {:homebrew, brew_upgrade_command()}

      :direct ->
        do_update(executable_path, opts)
    end
  end

  def current_executable do
    cond do
      (burrito_bin = System.get_env("__BURRITO_BIN_PATH")) && File.exists?(burrito_bin) ->
        {:ok, burrito_bin}

      (script = List.to_string(:escript.script_name())) != "" ->
        {:ok, Path.expand(script, File.cwd!())}

      exec = System.find_executable("inkwell") ->
        {:ok, exec}

      true ->
        {:error, :executable_not_found}
    end
  end

  defp current_executable! do
    case current_executable() do
      {:ok, path} -> path
      {:error, :executable_not_found} -> raise "Unable to locate inkwell executable"
    end
  end

  def current_version do
    Application.spec(:inkwell, :vsn) |> to_string()
  end

  def install_method(path) when is_binary(path) do
    resolved = resolve_symlinks(path)

    if Enum.any?(@homebrew_prefixes, &String.starts_with?(resolved, &1)),
      do: :homebrew,
      else: :direct
  end

  defp resolve_symlinks(path) do
    case File.read_link(path) do
      {:ok, target} ->
        target
        |> Path.expand(Path.dirname(path))
        |> resolve_symlinks()

      {:error, _} ->
        path
    end
  end

  def platform_asset_name(os_type \\ :os.type(), architecture \\ system_architecture()) do
    case {os_type, architecture_slug(architecture)} do
      {{:unix, :darwin}, :arm64} -> {:ok, "inkwell_darwin_arm64"}
      {{:unix, :darwin}, :amd64} -> {:ok, "inkwell_darwin_amd64"}
      {{:unix, :linux}, :amd64} -> {:ok, "inkwell_linux_amd64"}
      _ -> {:error, :unsupported_platform}
    end
  end

  def brew_upgrade_command, do: "brew upgrade zimakki/tap/inkwell-cli"

  defp do_update(executable_path, opts) do
    with {:ok, release} <- fetch_release(opts),
         {:ok, latest} <- release_version(release),
         current = Keyword.get(opts, :current_version, current_version()),
         :gt <- Version.compare(latest, current),
         {:ok, asset_name} <-
           platform_asset_name(
             Keyword.get(opts, :os_type, :os.type()),
             Keyword.get(opts, :architecture, system_architecture())
           ),
         {:ok, binary_url} <- asset_url(release, asset_name),
         {:ok, checksums_url} <- asset_url(release, "checksums.txt"),
         download_fn = Keyword.get(opts, :download_fn, &Inkwell.GitHub.download_binary/2),
         {:ok, binary_body} <- download_fn.(binary_url, Inkwell.GitHub.request_headers()),
         {:ok, checksums_body} <- download_fn.(checksums_url, Inkwell.GitHub.request_headers()),
         :ok <- verify_checksum(asset_name, binary_body, checksums_body),
         :ok <-
           replace_executable(executable_path, binary_body, Keyword.get(opts, :file_module, File)) do
      {:updated, %{current: current, latest: latest, executable_path: executable_path}}
    else
      :eq ->
        {:up_to_date, %{current: Keyword.get(opts, :current_version, current_version())}}

      :lt ->
        {:up_to_date, %{current: Keyword.get(opts, :current_version, current_version())}}

      {:error, _} = error ->
        error
    end
  end

  defp fetch_release(opts) do
    fetch_release_fn = Keyword.get(opts, :fetch_release_fn, &fetch_latest_release/1)
    fetch_release_fn.(Inkwell.GitHub.request_headers())
  end

  defp fetch_latest_release(headers) do
    case Inkwell.GitHub.download_binary(@latest_release_url, headers) do
      {:ok, body} -> Jason.decode(body)
      {:error, _} = error -> error
    end
  end

  defp release_version(%{"tag_name" => tag_name}) do
    version = Inkwell.GitHub.normalize_version(tag_name)

    case Version.parse(version) do
      {:ok, _} -> {:ok, version}
      :error -> {:error, {:invalid_version, tag_name}}
    end
  end

  defp release_version(_), do: {:error, :missing_tag_name}

  defp asset_url(%{"assets" => assets}, name) when is_list(assets) do
    case Enum.find(assets, &(&1["name"] == name)) do
      %{"browser_download_url" => url} -> {:ok, url}
      _ -> {:error, {:missing_asset, name}}
    end
  end

  defp asset_url(_, name), do: {:error, {:missing_asset, name}}

  defp verify_checksum(asset_name, binary_body, checksums_body) do
    checksum = :crypto.hash(:sha256, binary_body) |> Base.encode16(case: :lower)

    case expected_checksum(checksums_body, asset_name) do
      {:ok, ^checksum} -> :ok
      {:ok, _other} -> {:error, :checksum_mismatch}
      {:error, _} = error -> error
    end
  end

  defp expected_checksum(checksums_body, asset_name) do
    checksums_body
    |> String.split("\n", trim: true)
    |> Enum.find_value({:error, {:missing_checksum, asset_name}}, fn line ->
      case String.split(line, ~r/\s+/, parts: 2, trim: true) do
        [checksum, filename] ->
          if String.trim_leading(filename, "*") == asset_name, do: {:ok, checksum}, else: false

        _ ->
          false
      end
    end)
  end

  defp replace_executable(executable_path, binary_body, file_module) do
    temp_path = executable_path <> ".download"
    backup_path = executable_path <> ".bak"

    with :ok <- file_module.write(temp_path, binary_body, [:binary]),
         :ok <- maybe_chmod(file_module, temp_path),
         :ok <- safe_replace(file_module, executable_path, temp_path, backup_path) do
      :ok
    else
      {:error, _} = error ->
        file_module.rm(temp_path)
        error
    end
  end

  defp safe_replace(file_module, executable_path, temp_path, backup_path) do
    file_module.rm(backup_path)

    with :ok <- file_module.rename(executable_path, backup_path),
         :ok <- file_module.rename(temp_path, executable_path) do
      file_module.rm(backup_path)
      :ok
    else
      {:error, _} = error ->
        file_module.rm(temp_path)

        if file_module.exists?(backup_path) do
          _ = file_module.rename(backup_path, executable_path)
        end

        error
    end
  end

  defp maybe_chmod(file_module, path) do
    case :os.type() do
      {:win32, _} -> :ok
      _ -> file_module.chmod(path, 0o755)
    end
  end

  defp system_architecture do
    :erlang.system_info(:system_architecture) |> List.to_string()
  end

  defp architecture_slug(architecture) when is_list(architecture) do
    architecture |> List.to_string() |> architecture_slug()
  end

  defp architecture_slug(architecture) when is_binary(architecture) do
    cond do
      String.starts_with?(architecture, "aarch64") -> :arm64
      String.starts_with?(architecture, "arm64") -> :arm64
      String.starts_with?(architecture, "x86_64") -> :amd64
      String.starts_with?(architecture, "amd64") -> :amd64
      true -> :unknown
    end
  end
end
