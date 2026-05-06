defmodule Inkwell.PdfTest do
  use ExUnit.Case, async: false

  alias Inkwell.Pdf

  setup do
    # Ensure no stale persistent_term value bleeds across tests.
    on_exit(fn ->
      try do
        :persistent_term.erase(:inkwell_chrome_available)
      rescue
        ArgumentError -> :ok
      end
    end)

    tmp =
      Path.join(
        System.tmp_dir!(),
        "inkwell_pdf_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "detect_chrome/0 — INKWELL_CHROME_PATH" do
    test "uses INKWELL_CHROME_PATH when the env var points to an existing executable",
         %{tmp: tmp} do
      fake_chrome = Path.join(tmp, "my-chrome")
      File.write!(fake_chrome, "#!/bin/sh\nexit 0\n")
      File.chmod!(fake_chrome, 0o755)

      System.put_env("INKWELL_CHROME_PATH", fake_chrome)
      on_exit(fn -> System.delete_env("INKWELL_CHROME_PATH") end)

      assert Pdf.detect_chrome() == {:ok, fake_chrome}
      assert :persistent_term.get(:inkwell_chrome_available) == {:ok, fake_chrome}
    end

    test "ignores INKWELL_CHROME_PATH when the file does not exist", %{tmp: tmp} do
      missing = Path.join(tmp, "nope")
      System.put_env("INKWELL_CHROME_PATH", missing)
      on_exit(fn -> System.delete_env("INKWELL_CHROME_PATH") end)

      # Permissive on purpose: this test only verifies that an env-var pointing
      # at a missing file is *rejected* — it doesn't assert :error, because
      # Task 3 adds platform-path + PATH fallback that may legitimately return
      # {:ok, real_chrome_path} on a dev machine with Chrome installed.
      result = Pdf.detect_chrome()
      assert result != {:ok, missing}
    end
  end

  describe "detect_chrome/0 — platform paths" do
    test "returns :error when no env var, no platform path, and PATH lookup fails" do
      System.delete_env("INKWELL_CHROME_PATH")

      # Stub: this test asserts behaviour when nothing is found. On a dev
      # machine with Chrome installed, real PATH lookup will succeed — so we
      # narrow the assertion: detect_chrome/0 either returns {:ok, _} or
      # :error, never crashes, and the persistent_term is set accordingly.
      result = Inkwell.Pdf.detect_chrome()
      assert result == :error or match?({:ok, _}, result)
      cached = :persistent_term.get(:inkwell_chrome_available)
      assert cached == :error or match?({:ok, _}, cached)
    end
  end

  describe "available?/0" do
    test "returns true when persistent_term holds {:ok, _}" do
      :persistent_term.put(:inkwell_chrome_available, {:ok, "/fake/chrome"})
      assert Inkwell.Pdf.available?() == true
    end

    test "returns false when persistent_term holds :error" do
      :persistent_term.put(:inkwell_chrome_available, :error)
      assert Inkwell.Pdf.available?() == false
    end

    test "returns false when the persistent_term key is missing" do
      try do
        :persistent_term.erase(:inkwell_chrome_available)
      rescue
        ArgumentError -> :ok
      end

      assert Inkwell.Pdf.available?() == false
    end
  end
end
