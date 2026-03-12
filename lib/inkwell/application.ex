defmodule Inkwell.Application do
  @moduledoc "OTP application that starts the Inkwell supervision tree."

  use Application

  @doc """
  Parses CLI arguments into a mode (:daemon or :client) and parsed args.
  """
  def parse_mode(args) do
    {opts, rest, _invalid} = OptionParser.parse(args, strict: [theme: :string])
    theme = Keyword.get(opts, :theme, "dark")

    case rest do
      ["daemon"] ->
        {:daemon, %{theme: theme}}

      ["preview", file] ->
        {:client, %{command: :preview, file: file, theme: theme}}

      ["stop"] ->
        {:client, %{command: :stop}}

      ["status"] ->
        {:client, %{command: :status}}

      _ ->
        {:client, %{command: :usage}}
    end
  end

  @doc false
  def release? do
    not Code.ensure_loaded?(Mix)
  end

  @impl true
  def start(_type, _args) do
    {mode, parsed} =
      if release?() do
        args = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
        parse_mode(args)
      else
        {:daemon, %{theme: :persistent_term.get(:inkwell_theme, "dark")}}
      end

    children =
      case mode do
        :daemon ->
          :persistent_term.put(:inkwell_theme, parsed[:theme] || "dark")

          [
            {Registry, keys: :duplicate, name: Inkwell.Registry},
            {Inkwell.History, []},
            {Inkwell.Daemon, []},
            {DynamicSupervisor, strategy: :one_for_one, name: Inkwell.WatcherSupervisor},
            Supervisor.child_spec({Bandit, plug: Inkwell.Router, port: 0},
              id: Inkwell.BanditServer
            )
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
