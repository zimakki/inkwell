defmodule InkwellWeb.ExportComponentTest do
  use InkwellWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias InkwellWeb.ExportComponent

  defp render_component_with(assigns) do
    render_component(ExportComponent, assigns)
  end

  describe "render/1" do
    test "renders nothing when not open" do
      html =
        render_component_with(%{
          id: "export",
          open: false,
          current_path: "/tmp/x.md",
          chrome_available: true
        })

      refute html =~ "id=\"export-overlay\""
    end

    test "renders the modal when open" do
      html =
        render_component_with(%{
          id: "export",
          open: true,
          current_path: "/tmp/x.md",
          chrome_available: true
        })

      assert html =~ "id=\"export-overlay\""
      assert html =~ "Save as PDF"
      assert html =~ "Print"
    end

    test "primary action href reflects PDF preset defaults" do
      html =
        render_component_with(%{
          id: "export",
          open: true,
          current_path: "/tmp/doc.md",
          chrome_available: true
        })

      # PDF preset is the default. Expect a link to /export.pdf with theme=keep&toc=true&numbers=false&pagesize=a4&margins=normal.
      assert html =~ "href=\"/export.pdf?"
      assert html =~ "theme=keep"
      assert html =~ "toc=true"
      assert html =~ "numbers=false"
      assert html =~ "pagesize=a4"
      assert html =~ "margins=normal"
      assert html =~ ~s|path=#{URI.encode_www_form("/tmp/doc.md")}|
    end

    test "renders the disabled Save-as-PDF state when chrome_available is false" do
      html =
        render_component_with(%{
          id: "export",
          open: true,
          current_path: "/tmp/x.md",
          chrome_available: false
        })

      assert html =~ ~s|aria-disabled="true"|
      assert html =~ "Chrome not found"
      refute html =~ "href=\"/export.pdf?"
    end
  end

  describe "events" do
    test "select_preset switches form state to the print preset's defaults" do
      html =
        render_component_with(%{
          id: "export",
          open: true,
          current_path: "/tmp/doc.md",
          chrome_available: true
        })

      assert html =~ "checked"

      # Render with print preset selected (simulates the post-event state by passing form_state).
      print_state = %{
        preset: :print,
        theme: "print",
        toc: true,
        numbers: true,
        pagesize: "a4",
        margins: "normal"
      }

      html2 =
        render_component_with(%{
          id: "export",
          open: true,
          current_path: "/tmp/doc.md",
          chrome_available: true,
          form_state: print_state
        })

      assert html2 =~ "href=\"/print?"
      assert html2 =~ "autoprint=1"
      assert html2 =~ "theme=print"
      assert html2 =~ "numbers=true"
    end
  end
end
