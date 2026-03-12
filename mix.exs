defmodule Inkwell.MixProject do
  use Mix.Project

  def project do
    [
      app: :inkwell,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Inkwell.CLI, app: nil]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Inkwell.Application, []}
    ]
  end

  defp deps do
    [
      {:mdex, "~> 0.11"},
      {:bandit, "~> 1.10"},
      {:plug, "~> 1.19"},
      {:websock_adapter, "~> 0.5"},
      {:file_system, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
