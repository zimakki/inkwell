defmodule Inkwell.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()

  def project do
    [
      app: :inkwell,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
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
        usage_rules: [],
        skills: [
          location: ".claude/skills",
          build: [
            "ash-framework": [
              description:
                "Use when working with Ash resources, actions, queries, migrations, code interfaces, or any ash_* extension (incl. spark, reactor, igniter generators).",
              usage_rules: [:ash, :spark, :reactor, :igniter, ~r/^ash_/]
            ],
            "phoenix-framework": [
              description:
                "Use when working with the web layer — Phoenix routes, controllers, LiveViews, Ecto, HTML/HEEx components.",
              usage_rules: [:phoenix, ~r/^phoenix_/]
            ],
            "elixir-core": [
              description:
                "Use for general Elixir/OTP patterns — pattern matching, GenServers, supervision trees, Task, error handling.",
              usage_rules: [:usage_rules]
            ],
            mdex: [
              description:
                "Use when rendering markdown with MDEx — sigils, HEEx integration, streaming, plugins, syntax highlighting.",
              usage_rules: [:mdex]
            ]
          ]
        ]
      ],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :runtime_tools],
      mod: {Inkwell.Application, []}
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_sqlite, "~> 0.2"},
      {:ash, "~> 3.0"},
      {:mdex, "~> 0.11"},
      {:bandit, "~> 1.10"},
      {:plug, "~> 1.19"},
      {:file_system, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: [:dev, :test]},
      {:phoenix_test, "~> 0.10", only: [:dev, :test]},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:burrito, "~> 1.0", only: :prod},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:usage_rules, "~> 1.1", only: :dev},
      {:tidewave, "~> 0.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild inkwell"],
      "assets.deploy": ["esbuild inkwell --minify", "phx.digest"],
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
      files: ~w(lib priv mix.exs mix.lock README.md LICENSE VERSION)
    ]
  end
end
