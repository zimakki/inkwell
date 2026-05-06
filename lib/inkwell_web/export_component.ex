defmodule InkwellWeb.ExportComponent do
  @moduledoc """
  Export modal: lets the user pick "Save as PDF" or "Print" with overridable settings.

  Both submit actions are plain anchor-tag navigations:
    * Save as PDF → `<a href="/export.pdf?…" phx-click="close_export">`
    * Print       → `<a href="/print?autoprint=1&…" target="_blank" phx-click="close_export">`

  When ChromicPDF / Chrome is unavailable, the Save-as-PDF anchor is rendered
  inert (`aria-disabled`, no href, `.disabled` CSS rule).
  """

  use InkwellWeb, :live_component

  @pdf_defaults %{
    preset: :pdf,
    theme: "keep",
    toc: true,
    numbers: false,
    pagesize: "a4",
    margins: "normal"
  }

  @print_defaults %{
    preset: :print,
    theme: "print",
    toc: true,
    numbers: true,
    pagesize: "a4",
    margins: "normal"
  }

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:form_state, fn -> @pdf_defaults end)
      |> assign_new(:chrome_available, fn -> true end)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_preset", %{"preset" => "pdf"}, socket),
    do: {:noreply, assign(socket, :form_state, @pdf_defaults)}

  def handle_event("select_preset", %{"preset" => "print"}, socket),
    do: {:noreply, assign(socket, :form_state, @print_defaults)}

  def handle_event("update_form", params, socket) do
    state = socket.assigns.form_state

    new_state = %{
      state
      | theme: Map.get(params, "theme", state.theme),
        toc: parse_bool(Map.get(params, "toc"), state.toc),
        numbers: parse_bool(Map.get(params, "numbers"), state.numbers),
        pagesize: Map.get(params, "pagesize", state.pagesize),
        margins: Map.get(params, "margins", state.margins)
    }

    {:noreply, assign(socket, :form_state, new_state)}
  end

  defp parse_bool("true", _default), do: true
  defp parse_bool("false", _default), do: false
  defp parse_bool(nil, default), do: default
  defp parse_bool(_, default), do: default

  defp build_query(form_state, current_path) do
    URI.encode_query(%{
      "path" => current_path,
      "theme" => form_state.theme,
      "toc" => to_string(form_state.toc),
      "numbers" => to_string(form_state.numbers),
      "pagesize" => form_state.pagesize,
      "margins" => form_state.margins
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="export-root">
      <div :if={@open} id="export-overlay" phx-window-keydown="close_export" phx-key="Escape">
        <div id="export-backdrop" phx-click="close_export"></div>
        <div id="export-modal">
        <div id="export-presets">
          <button
            type="button"
            class={["preset-btn", @form_state.preset == :pdf && "active"]}
            phx-click="select_preset"
            phx-value-preset="pdf"
            phx-target={@myself}
          >
            Save as PDF
          </button>
          <button
            type="button"
            class={["preset-btn", @form_state.preset == :print && "active"]}
            phx-click="select_preset"
            phx-value-preset="print"
            phx-target={@myself}
          >
            Print
          </button>
        </div>

        <form id="export-form" phx-change="update_form" phx-target={@myself}>
          <fieldset>
            <legend>Theme</legend>
            <label>
              <input type="radio" name="theme" value="keep" checked={@form_state.theme == "keep"} />
              Keep current
            </label>
            <label>
              <input type="radio" name="theme" value="print" checked={@form_state.theme == "print"} />
              Printer-friendly
            </label>
          </fieldset>

          <fieldset>
            <legend>Contents (TOC page)</legend>
            <label>
              <input type="radio" name="toc" value="true" checked={@form_state.toc} /> On
            </label>
            <label>
              <input type="radio" name="toc" value="false" checked={not @form_state.toc} /> Off
            </label>
          </fieldset>

          <fieldset>
            <legend>Page numbers</legend>
            <label>
              <input type="radio" name="numbers" value="true" checked={@form_state.numbers} /> On
            </label>
            <label>
              <input type="radio" name="numbers" value="false" checked={not @form_state.numbers} /> Off
            </label>
          </fieldset>

          <label>
            Page size
            <select name="pagesize">
              <option value="a4" selected={@form_state.pagesize == "a4"}>A4</option>
              <option value="letter" selected={@form_state.pagesize == "letter"}>Letter</option>
              <option value="legal" selected={@form_state.pagesize == "legal"}>Legal</option>
            </select>
          </label>

          <label>
            Margins
            <select name="margins">
              <option value="normal" selected={@form_state.margins == "normal"}>Normal</option>
              <option value="narrow" selected={@form_state.margins == "narrow"}>Narrow</option>
              <option value="none" selected={@form_state.margins == "none"}>None</option>
            </select>
          </label>
        </form>

        <div id="export-actions">
          <%= if @form_state.preset == :pdf do %>
            <%= if @chrome_available do %>
              <a
                class="action-btn primary"
                href={"/export.pdf?" <> build_query(@form_state, @current_path)}
                phx-click="close_export"
              >
                Save as PDF
              </a>
            <% else %>
              <a
                class="action-btn primary disabled"
                aria-disabled="true"
                tabindex="-1"
                title="Chrome not found — install Chromium or Google Chrome to enable PDF export"
              >
                Save as PDF
              </a>
            <% end %>
          <% else %>
            <a
              class="action-btn primary"
              href={"/print?autoprint=1&" <> build_query(@form_state, @current_path)}
              target="_blank"
              phx-click="close_export"
            >
              Print…
            </a>
          <% end %>
          <button type="button" class="action-btn" phx-click="close_export">Cancel</button>
        </div>
        </div>
      </div>
    </div>
    """
  end
end
