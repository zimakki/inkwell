defmodule Mix.Tasks.BumpTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "patches version into target files", %{tmp_dir: tmp_dir} do
    version_file = Path.join(tmp_dir, "VERSION")
    mix_file = Path.join(tmp_dir, "mix.exs")
    cargo_file = Path.join(tmp_dir, "Cargo.toml")
    json_file = Path.join(tmp_dir, "tauri.conf.json")

    File.write!(version_file, "1.2.3\n")
    File.write!(mix_file, ~s|version: "0.0.0"|)
    File.write!(cargo_file, ~s|version = "0.0.0"|)
    File.write!(json_file, ~s|"version": "0.0.0"|)

    version = File.read!(version_file) |> String.trim()

    assert Regex.match?(~r/^\d+\.\d+\.\d+$/, version)

    for {path, pattern, replacement} <- [
          {mix_file, ~r/version: "[\d.]+"/, ~s(version: "#{version}")},
          {cargo_file, ~r/^version = "[\d.]+"$/m, ~s(version = "#{version}")},
          {json_file, ~r/"version": "[\d.]+"/, ~s("version": "#{version}")}
        ] do
      content = File.read!(path)
      assert Regex.match?(pattern, content)
      updated = Regex.replace(pattern, content, replacement, global: false)
      File.write!(path, updated)
    end

    assert File.read!(mix_file) == ~s|version: "1.2.3"|
    assert File.read!(cargo_file) == ~s|version = "1.2.3"|
    assert File.read!(json_file) == ~s|"version": "1.2.3"|
  end

  test "rejects invalid semver" do
    refute Regex.match?(~r/^\d+\.\d+\.\d+$/, "not-a-version")
    refute Regex.match?(~r/^\d+\.\d+\.\d+$/, "1.2")
    refute Regex.match?(~r/^\d+\.\d+\.\d+$/, "")
    assert Regex.match?(~r/^\d+\.\d+\.\d+$/, "0.2.21")
  end
end
