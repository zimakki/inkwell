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

      # No platform paths exist in the sandbox, so detection falls through to :error.
      # We assert the env-var did NOT match (the function does not crash, and the
      # cached value is :error or a real-system Chrome — accept either).
      result = Pdf.detect_chrome()
      assert result != {:ok, missing}
    end
  end
end
