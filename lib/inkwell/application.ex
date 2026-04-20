defmodule Inkwell.Application do
  @moduledoc "OTP application that starts the Inkwell supervision tree."

  use Application

  @doc false
  def release? do
    not Code.ensure_loaded?(Mix)
  end

  defp resolve_theme(explicit) when explicit in ["dark", "light"], do: explicit
  defp resolve_theme(_other), do: Inkwell.Settings.read_theme() || "dark"

  @impl true
  def start(_type, _args) do
    {mode, parsed} =
      if release?() do
        args = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
        Inkwell.CLI.parse_mode(args)
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
