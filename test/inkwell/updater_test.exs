defmodule Inkwell.UpdaterTest do
  use ExUnit.Case, async: true

  test "install_method detects Homebrew prefixes" do
    assert Inkwell.Updater.install_method("/opt/homebrew/bin/inkwell") == :homebrew

    assert Inkwell.Updater.install_method("/usr/local/Cellar/inkwell-cli/0.2.12/bin/inkwell") ==
             :homebrew

    assert Inkwell.Updater.install_method("/home/linuxbrew/.linuxbrew/bin/inkwell") == :homebrew
    assert Inkwell.Updater.install_method("/tmp/inkwell") == :direct
  end

  test "platform_asset_name maps supported targets" do
    assert Inkwell.Updater.platform_asset_name({:unix, :darwin}, "aarch64-apple-darwin") ==
             {:ok, "inkwell_darwin_arm64"}

    assert Inkwell.Updater.platform_asset_name({:unix, :darwin}, "x86_64-apple-darwin") ==
             {:ok, "inkwell_darwin_amd64"}

    assert Inkwell.Updater.platform_asset_name({:unix, :linux}, "x86_64-unknown-linux-gnu") ==
             {:ok, "inkwell_linux_amd64"}
  end

  test "check returns update availability with install method" do
    release = %{"tag_name" => "v0.3.0", "assets" => []}

    assert {:update_available, %{current: "0.2.12", latest: "0.3.0", install_method: :direct}} =
             Inkwell.Updater.check(
               current_version: "0.2.12",
               executable_path: "/tmp/inkwell",
               fetch_release_fn: fn _headers -> {:ok, release} end
             )
  end

  test "update replaces a direct-install binary after checksum verification" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "inkwell-updater-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    executable_path = Path.join(tmp_dir, "inkwell")
    File.write!(executable_path, "old-binary")

    binary_body = "new-binary"
    checksum = :crypto.hash(:sha256, binary_body) |> Base.encode16(case: :lower)

    release = %{
      "tag_name" => "v0.3.0",
      "assets" => [
        %{
          "name" => "inkwell_darwin_arm64",
          "browser_download_url" => "https://example.test/inkwell_darwin_arm64"
        },
        %{
          "name" => "checksums.txt",
          "browser_download_url" => "https://example.test/checksums.txt"
        }
      ]
    }

    download_fn = fn
      "https://example.test/inkwell_darwin_arm64", _headers ->
        {:ok, binary_body}

      "https://example.test/checksums.txt", _headers ->
        {:ok, "#{checksum}  inkwell_darwin_arm64\n"}
    end

    assert {:updated, %{current: "0.2.12", latest: "0.3.0", executable_path: ^executable_path}} =
             Inkwell.Updater.update(
               current_version: "0.2.12",
               executable_path: executable_path,
               os_type: {:unix, :darwin},
               architecture: "aarch64-apple-darwin",
               fetch_release_fn: fn _headers -> {:ok, release} end,
               download_fn: download_fn
             )

    assert File.read!(executable_path) == "new-binary"
  end

  test "update returns Homebrew instructions for homebrew installs" do
    assert {:homebrew, "brew upgrade zimakki/tap/inkwell-cli"} =
             Inkwell.Updater.update(executable_path: "/opt/homebrew/bin/inkwell")
  end
end
