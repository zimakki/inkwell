defmodule Inkwell.MixProject do
  use Mix.Project

  def project do
    [
      app: :inkwell,
      version: "0.2.20",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      name: "Inkwell",
      source_url: "https://github.com/zimakki/inkwell",
      homepage_url: "https://github.com/zimakki/inkwell",
      docs: [main: "readme", extras: ["README.md"]],
      package: package(),
      aliases: aliases(),
      usage_rules: [
        file: "CLAUDE.md",
        usage_rules: :all
      ]
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
      {:jason, "~> 1.4"},
      {:burrito, "~> 1.0", only: :prod},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:usage_rules, "~> 1.1", only: :dev},
      {:tidewave, "~> 0.5", only: :dev}
    ]
  end

  defp aliases do
    [
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
    ]
  end

  defp releases do
    [
      inkwell: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            darwin_arm64: [os: :darwin, cpu: :aarch64],
            darwin_amd64: [os: :darwin, cpu: :x86_64],
            linux_amd64: [os: :linux, cpu: :x86_64],
            windows_amd64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp package do
    [
      description: "Live markdown preview daemon with file picker and fuzzy search",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/zimakki/inkwell"},
      files: ~w(lib priv mix.exs mix.lock README.md LICENSE)
    ]
  end
end
