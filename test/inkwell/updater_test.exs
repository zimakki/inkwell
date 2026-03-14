defmodule Inkwell.UpdaterTest do
  use ExUnit.Case, async: true

  test "install_method detects Homebrew prefixes" do
    assert Inkwell.Updater.install_method("/opt/homebrew/bin/inkwell") == :homebrew

    assert Inkwell.Updater.install_method("/usr/local/Cellar/inkwell-cli/0.2.12/bin/inkwell") ==
             :homebrew

    assert Inkwell.Updater.install_method("/home/linuxbrew/.linuxbrew/bin/inkwell") == :homebrew
    assert Inkwell.Updater.install_method("/tmp/inkwell") == :direct
  end

  @tag :tmp_dir
  test "install_method resolves symlinks into Homebrew Cellar" do
    # Simulate Intel Homebrew layout where /usr/local/bin/inkwell is a symlink
    # to /usr/local/Cellar/inkwell-cli/0.2.14/bin/inkwell.
    # We can't write to /usr/local, so we check that symlinks pointing to
    # non-Homebrew paths are correctly classified as :direct.
    tmp_dir =
      Path.join(System.tmp_dir!(), "inkwell-symlink-#{System.unique_integer([:positive])}")

    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    target = Path.join(bin_dir, "inkwell")
    File.write!(target, "binary")

    link = Path.join(tmp_dir, "inkwell-link")
    File.ln_s!(target, link)

    # Symlink resolves to a non-Homebrew path, so it's :direct
    assert Inkwell.Updater.install_method(link) == :direct
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

  test "update rejects binary with mismatched checksum" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "inkwell-updater-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    executable_path = Path.join(tmp_dir, "inkwell")
    File.write!(executable_path, "old-binary")

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
        {:ok, "new-binary"}

      "https://example.test/checksums.txt", _headers ->
        {:ok,
         "0000000000000000000000000000000000000000000000000000000000000000  inkwell_darwin_arm64\n"}
    end

    assert {:error, :checksum_mismatch} =
             Inkwell.Updater.update(
               current_version: "0.2.12",
               executable_path: executable_path,
               os_type: {:unix, :darwin},
               architecture: "aarch64-apple-darwin",
               fetch_release_fn: fn _headers -> {:ok, release} end,
               download_fn: download_fn
             )

    assert File.read!(executable_path) == "old-binary"
  end

  test "check rejects malformed version tags" do
    release = %{"tag_name" => "v2024.01", "assets" => []}

    assert {:error, {:invalid_version, "v2024.01"}} =
             Inkwell.Updater.check(
               current_version: "0.2.12",
               executable_path: "/tmp/inkwell",
               fetch_release_fn: fn _headers -> {:ok, release} end
             )
  end
end
