defmodule Inkwell.DocNavTest do
  use ExUnit.Case, async: true

  alias Inkwell.DocNav

  # ── extract_headings/1 ─────────────────────────

  test "extracts h2 and h3 headings" do
    md = "# H1\n## Getting Started\n### Installation\n## Usage\n"

    headings = DocNav.extract_headings(md)

    assert headings == [
             %{level: 2, text: "Getting Started", id: "getting-started"},
             %{level: 3, text: "Installation", id: "installation"},
             %{level: 2, text: "Usage", id: "usage"}
           ]
  end

  test "ignores h1 and h4+ headings" do
    md = "# Title\n#### Deep\n##### Deeper\n## Keep This\n"

    headings = DocNav.extract_headings(md)

    assert headings == [%{level: 2, text: "Keep This", id: "keep-this"}]
  end

  test "slugifies special characters and unicode" do
    md = "## What's New?\n## Héllo Wörld\n"

    headings = DocNav.extract_headings(md)

    # \w with /u flag preserves unicode word chars (accented letters)
    assert [%{id: "whats-new"}, %{id: "héllo-wörld"}] = headings
  end

  test "strips inline markdown from heading text" do
    md = "## **Bold** heading\n## A `code` thing\n## [Link text](http://x)\n"

    headings = DocNav.extract_headings(md)

    assert [
             %{text: "Bold heading"},
             %{text: "A code thing"},
             %{text: "Link text"}
           ] = headings
  end

  test "returns empty list for no headings" do
    assert DocNav.extract_headings("Just a paragraph.\n") == []
  end

  test "trims whitespace from heading text" do
    md = "##   Spaced Out   \n"

    [%{text: text, id: id}] = DocNav.extract_headings(md)

    assert text == "Spaced Out"
    assert id == "spaced-out"
  end

  # ── extract_alerts/1 ───────────────────────────

  test "extracts alerts with bold title" do
    md = """
    > [!WARNING]
    > **Memory leak** detected in worker pool.
    """

    alerts = DocNav.extract_alerts(md)

    assert [%{type: "warning", title: "Memory leak", id: "alert-warning-1"}] = alerts
  end

  test "falls back to first line when no bold title" do
    md = """
    > [!NOTE]
    > Check the logs for details.
    """

    alerts = DocNav.extract_alerts(md)

    assert [%{type: "note", title: "Check the logs for details."}] = alerts
  end

  test "falls back to capitalized type for empty body" do
    md = """
    > [!TIP]
    >
    """

    alerts = DocNav.extract_alerts(md)

    assert [%{type: "tip", title: "Tip"}] = alerts
  end

  test "strips common prefixes from bold titles" do
    md = """
    > [!WARNING]
    > **WARNING — Do not run in production**
    """

    alerts = DocNav.extract_alerts(md)

    assert [%{title: "Do not run in production"}] = alerts
  end

  test "sorts alerts by type priority" do
    md = """
    > [!TIP]
    > A tip

    > [!WARNING]
    > A warning

    > [!NOTE]
    > A note
    """

    alerts = DocNav.extract_alerts(md)

    assert [%{type: "warning"}, %{type: "note"}, %{type: "tip"}] = alerts
  end

  test "assigns incrementing IDs per alert type" do
    md = """
    > [!WARNING]
    > First warning

    > [!NOTE]
    > A note

    > [!WARNING]
    > Second warning
    """

    alerts = DocNav.extract_alerts(md)

    warning_ids = alerts |> Enum.filter(&(&1.type == "warning")) |> Enum.map(& &1.id)
    assert warning_ids == ["alert-warning-1", "alert-warning-2"]

    note_ids = alerts |> Enum.filter(&(&1.type == "note")) |> Enum.map(& &1.id)
    assert note_ids == ["alert-note-1"]
  end

  test "extracts alert at end of file without trailing newline" do
    md = "> [!WARNING]\n> No trailing newline"

    alerts = DocNav.extract_alerts(md)

    assert [%{type: "warning"}] = alerts
  end

  test "returns empty list for no alerts" do
    assert DocNav.extract_alerts("Just text\n") == []
  end

  # ── inject_heading_ids/2 ───────────────────────

  test "injects id attributes into h2/h3 tags" do
    html = "<h2>Getting Started</h2><h3>Installation</h3>"

    headings = [
      %{level: 2, text: "Getting Started", id: "getting-started"},
      %{level: 3, text: "Installation", id: "installation"}
    ]

    result = DocNav.inject_heading_ids(html, headings)

    assert result =~ ~s(<h2 id="getting-started">Getting Started</h2>)
    assert result =~ ~s(<h3 id="installation">Installation</h3>)
  end

  test "does not re-inject id on elements that already have one" do
    html = ~s(<h2 id="existing">Title</h2>)
    headings = [%{level: 2, text: "Title", id: "title"}]

    result = DocNav.inject_heading_ids(html, headings)

    assert result == html
  end

  test "handles regex-special characters in heading text" do
    html = "<h2>What (and why)?</h2>"
    headings = [%{level: 2, text: "What (and why)?", id: "what-and-why"}]

    result = DocNav.inject_heading_ids(html, headings)

    assert result =~ ~s(id="what-and-why")
  end

  # ── inject_alert_ids/2 ─────────────────────────

  test "injects id into alert divs" do
    html = ~s(<div class="markdown-alert markdown-alert-warning">\n<p>Watch out</p>\n</div>)
    alerts = [%{type: "warning", title: "Watch out", id: "alert-warning-1"}]

    result = DocNav.inject_alert_ids(html, alerts)

    assert result =~ ~s(id="alert-warning-1")
  end

  test "injects ids into correct nth occurrence of same type" do
    html =
      ~s(<div class="markdown-alert markdown-alert-warning">\n<p>First</p>\n</div>\n) <>
        ~s(<div class="markdown-alert markdown-alert-warning">\n<p>Second</p>\n</div>)

    alerts = [
      %{type: "warning", title: "First", id: "alert-warning-1"},
      %{type: "warning", title: "Second", id: "alert-warning-2"}
    ]

    result = DocNav.inject_alert_ids(html, alerts)

    assert result =~ ~s(id="alert-warning-1")
    assert result =~ ~s(id="alert-warning-2")
  end

  # ── process/2 (full pipeline) ──────────────────

  test "process returns enriched HTML with headings and alerts" do
    md = "## Overview\n### Details\n\n> [!NOTE]\n> Remember this.\n"

    html =
      MDEx.to_html!(md,
        extension: [alerts: true],
        render: [unsafe: true]
      )

    {enriched, headings, alerts} = DocNav.process(md, html)

    assert length(headings) == 2
    assert hd(headings).text == "Overview"

    assert length(alerts) == 1
    assert hd(alerts).type == "note"

    assert enriched =~ ~s(id="overview")
    assert enriched =~ ~s(id="details")
  end

  test "process handles markdown with no nav elements" do
    md = "Just a paragraph.\n"
    html = MDEx.to_html!(md, render: [unsafe: true])

    {enriched, headings, alerts} = DocNav.process(md, html)

    assert headings == []
    assert alerts == []
    assert enriched == html
  end
end
