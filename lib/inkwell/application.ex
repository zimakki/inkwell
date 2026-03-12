defmodule Inkwell.Application do
  @moduledoc "OTP application that starts the Inkwell supervision tree."

  use Application

  @impl true
  def start(_type, _args) do
    :persistent_term.put(:inkwell_theme, :persistent_term.get(:inkwell_theme, "dark"))

    children = [
      {Registry, keys: :duplicate, name: Inkwell.Registry},
      {Inkwell.History, []},
      {Inkwell.Daemon, []},
      {DynamicSupervisor, strategy: :one_for_one, name: Inkwell.WatcherSupervisor},
      Supervisor.child_spec({Bandit, plug: Inkwell.Router, port: 0}, id: Inkwell.BanditServer)
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Inkwell.Supervisor)
  end
end
