defmodule Inkwell.Application do
  @moduledoc "OTP application that starts the Inkwell supervision tree."

  use Application

  @doc """
  Parses CLI arguments into a mode (:daemon or :client) and parsed args.
  """
  def parse_mode(args) do
    {opts, rest, _invalid} =
      OptionParser.parse(args,
        strict: [theme: :string, help: :boolean, version: :boolean],
        aliases: [h: :help, v: :version]
      )

    # nil means "no --theme flag was passed" — Application.start will fall back
    # to the persisted theme (or "dark" on first boot). Client commands keep
    # this nil and only inject --theme into the spawned daemon when explicitly
    # provided, so launching the daemon doesn't clobber the user's last choice.
    theme = opts[:theme]

    cond do
      opts[:help] ->
        {:client, %{command: :help}}

      opts[:version] ->
        {:client, %{command: :version}}

      true ->
        case rest do
          ["daemon"] ->
            {:daemon, %{theme: theme}}

          ["preview", file] ->
            {:client, %{command: :preview, file: file, theme: theme, deprecated: true}}

          ["stop"] ->
            {:client, %{command: :stop}}

          ["status"] ->
            {:client, %{command: :status}}

          [path] ->
            case classify_path(path) do
              :file ->
                {:client, %{command: :preview, file: path, theme: theme}}

              :directory ->
                {:client, %{command: :browse, dir: path, theme: theme}}

              :not_found ->
                {:client, %{command: :path_not_found, path: path}}
            end

          [] ->
            {:client, %{command: :usage}}

          _ ->
            {:client, %{command: :usage}}
        end
    end
  end

  @doc false
  def release? do
    not Code.ensure_loaded?(Mix)
  end

  @doc """
  Classifies a path as `:file`, `:directory`, or `:not_found`.

  Symlinks are followed (uses `File.stat/1`, not `File.lstat/1`).
  Anything that isn't a regular file or directory — device nodes,
  sockets, broken symlinks, stat errors — is reported as `:not_found`.
  """
  @spec classify_path(Path.t()) :: :file | :directory | :not_found
  def classify_path(path) do
    case File.stat(Path.expand(path)) do
      {:ok, %File.Stat{type: :regular}} -> :file
      {:ok, %File.Stat{type: :directory}} -> :directory
      _ -> :not_found
    end
  end

  defp resolve_theme(explicit) when explicit in ["dark", "light"], do: explicit
  defp resolve_theme(_other), do: Inkwell.Settings.read_theme() || "dark"

  @impl true
  def start(_type, _args) do
    {mode, parsed} =
      if release?() do
        args = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
        parse_mode(args)
      else
        # nil flows through resolve_theme/1 → persisted → "dark" default.
        {:daemon, %{theme: nil}}
      end

    children =
      case mode do
        :daemon ->
          theme = resolve_theme(parsed[:theme])
          :persistent_term.put(:inkwell_theme, theme)
          if parsed[:theme], do: Inkwell.Settings.write_theme(theme)

          Inkwell.Release.migrate!()
          Inkwell.GitRepo.init_cache()

          [
            {Phoenix.PubSub, name: Inkwell.PubSub},
            {Registry, keys: :unique, name: Inkwell.WatcherRegistry},
            Inkwell.Repo,
            {Inkwell.History, []},
            {Inkwell.Daemon, []},
            {DynamicSupervisor, strategy: :one_for_one, name: Inkwell.WatcherSupervisor},
            InkwellWeb.Telemetry,
            InkwellWeb.Endpoint
          ]

        :client ->
          []
      end

    {:ok, pid} =
      Supervisor.start_link(children, strategy: :one_for_one, name: Inkwell.Supervisor)

    # In client mode, run_client_command calls System.halt() so the line
    # below is only reached in daemon mode.
    if mode == :client, do: Inkwell.CLI.run_client_command(parsed)

    {:ok, pid}
  end
end
