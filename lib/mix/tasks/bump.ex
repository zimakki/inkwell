defmodule Mix.Tasks.Bump do
  @moduledoc """
  Reads the version from the VERSION file and patches it into all release metadata files.

  Updates:
    - mix.exs
    - src-tauri/Cargo.toml
    - src-tauri/tauri.conf.json
    - src-tauri/Cargo.lock (via `cargo check`)

  ## Usage

      mix bump
  """

  use Mix.Task

  @shortdoc "Sync VERSION file into mix.exs, Cargo.toml, tauri.conf.json, and Cargo.lock"

  @impl Mix.Task
  def run(_args) do
    version =
      "VERSION"
      |> File.read!()
      |> String.trim()

    unless Regex.match?(~r/^\d+\.\d+\.\d+$/, version) do
      Mix.raise(
        "VERSION file must contain a valid semver string (e.g. 1.2.3), got: #{inspect(version)}"
      )
    end

    patch_file("mix.exs", ~r/version: "[\d.]+"/, ~s(version: "#{version}"))
    patch_file("src-tauri/Cargo.toml", ~r/^version = "[\d.]+"$/m, ~s(version = "#{version}"))
    patch_file("src-tauri/tauri.conf.json", ~r/"version": "[\d.]+"/, ~s("version": "#{version}"))

    Mix.shell().info("Running cargo check to update Cargo.lock...")

    {_, exit_code} =
      System.cmd("cargo", ["check"], cd: "src-tauri", stderr_to_stdout: true)

    if exit_code != 0 do
      Mix.raise("cargo check failed — Cargo.lock may not be updated")
    end

    Mix.shell().info("All files bumped to #{version}")
  end

  defp patch_file(path, pattern, replacement) do
    content = File.read!(path)

    unless Regex.match?(pattern, content) do
      Mix.raise("Could not find version pattern in #{path}")
    end

    updated = Regex.replace(pattern, content, replacement, global: false)
    File.write!(path, updated)
    Mix.shell().info("  ✓ #{path}")
  end
end
