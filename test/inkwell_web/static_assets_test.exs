defmodule InkwellWeb.StaticAssetsTest do
  use ExUnit.Case, async: true

  @markdown_css Path.join([File.cwd!(), "priv", "static", "markdown-wide.css"])

  describe "markdown-wide.css" do
    setup do
      {:ok, css: File.read!(@markdown_css)}
    end

    test "styles every GitHub-style alert type", %{css: css} do
      for type <- ~w(note tip important warning caution) do
        assert css =~ ".markdown-alert-#{type}",
               "expected .markdown-alert-#{type} selector in markdown-wide.css"
      end
    end

    test "styles the alert title", %{css: css} do
      assert css =~ ".markdown-alert-title"
    end
  end
end
