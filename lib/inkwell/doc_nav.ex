defmodule Inkwell.DocNav do
  @moduledoc "Extracts headings and alerts from markdown, injects matching IDs into rendered HTML."

  @alert_order %{"warning" => 0, "note" => 1, "tip" => 2, "important" => 3, "caution" => 4}

  @doc "Extract h2/h3 headings from raw markdown. Returns list of %{level, text, id}."
  def extract_headings(markdown) do
    markdown
    |> MDEx.parse_document!()
    |> collect_headings()
    |> deduplicate_slugs()
  end

  defp collect_headings(doc) do
    doc
    |> Enum.flat_map(fn
      %MDEx.Heading{level: level, nodes: nodes} when level in [2, 3] ->
        text = nodes |> heading_text() |> String.trim()
        [%{level: level, text: text, id: slugify(text)}]

      _ ->
        []
    end)
  end

  defp heading_text(nodes) do
    Enum.map_join(nodes, "", fn
      %MDEx.Text{literal: t} -> t
      %MDEx.Code{literal: t} -> t
      %MDEx.Strong{nodes: inner} -> heading_text(inner)
      %MDEx.Emph{nodes: inner} -> heading_text(inner)
      %MDEx.Link{nodes: inner} -> heading_text(inner)
      %MDEx.Strikethrough{nodes: inner} -> heading_text(inner)
      _ -> ""
    end)
  end

  defp deduplicate_slugs(headings) do
    headings
    |> Enum.map_reduce(%{}, fn %{id: id} = h, counts ->
      case Map.get(counts, id, 0) do
        0 -> {h, Map.put(counts, id, 1)}
        n -> {%{h | id: "#{id}-#{n}"}, Map.put(counts, id, n + 1)}
      end
    end)
    |> elem(0)
  end

  @doc "Extract GitHub-style alerts from raw markdown. Returns list of %{type, title, id}."
  def extract_alerts(markdown) do
    ~r/> \[!(WARNING|NOTE|TIP|IMPORTANT|CAUTION)\]\n?((?:>.*\n?)*)/mu
    |> Regex.scan(markdown)
    |> Enum.reduce({[], %{}}, fn [_, type_raw, body], {acc, counts} ->
      type = String.downcase(type_raw)
      count = Map.get(counts, type, 0) + 1
      title = extract_alert_title(body, type)
      id = "alert-#{type}-#{count}"
      {[%{type: type, title: title, id: id} | acc], Map.put(counts, type, count)}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.sort_by(fn %{type: t} -> Map.get(@alert_order, t, 99) end)
  end

  @doc "Inject id attributes onto h2/h3 elements in rendered HTML."
  def inject_heading_ids(html, headings) do
    Enum.reduce(headings, html, fn %{id: id, text: text}, acc ->
      escaped = Regex.escape(text)
      # Match <h2> or <h3> tags that don't already have an id, containing the heading text
      pattern = ~r/(<h[23])(?![^>]*\bid=)([^>]*>)\s*(#{escaped})/u
      Regex.replace(pattern, acc, "\\1 id=\"#{id}\"\\2\\3", global: false)
    end)
  end

  @doc "Inject id attributes onto markdown-alert divs in rendered HTML."
  def inject_alert_ids(html, alerts) do
    # Each injection modifies the div so it no longer matches the bare pattern,
    # so we always target the first unmodified match (skip_count = 0).
    Enum.reduce(alerts, html, fn %{type: type, id: id}, acc ->
      {replaced, _} = inject_nth_alert_id(acc, type, 0, id)
      replaced
    end)
  end

  defp inject_nth_alert_id(html, type, skip_count, id) do
    pattern = ~r/<div class="markdown-alert markdown-alert-#{type}">/u

    parts = Regex.split(pattern, html, include_captures: true)

    parts
    |> Enum.reduce({[], 0}, fn part, {acc, seen} ->
      if Regex.match?(pattern, part) do
        if seen == skip_count do
          replaced = String.replace(part, ">", " id=\"#{id}\">", global: false)
          {[replaced | acc], seen + 1}
        else
          {[part | acc], seen + 1}
        end
      else
        {[part | acc], seen}
      end
    end)
    |> then(fn {parts, count} -> {parts |> Enum.reverse() |> Enum.join(), count} end)
  end

  @doc "Full pipeline: extract nav data from markdown, inject IDs into rendered HTML."
  def process(markdown, html) do
    headings = extract_headings(markdown)
    alerts = extract_alerts(markdown)

    enriched_html =
      html
      |> inject_heading_ids(headings)
      |> inject_alert_ids(alerts)

    {enriched_html, headings, alerts}
  end

  defp extract_alert_title(body, type) do
    # Strip leading "> " from each line
    clean =
      body
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        line
        |> String.replace_prefix("> ", "")
        |> String.replace_prefix(">", "")
      end)
      |> String.trim()

    # Try to extract first bold text
    case Regex.run(~r/\*\*(.+?)\*\*/u, clean) do
      [_, title] ->
        # Strip common prefixes like "CRITIQUE —" or "Warning:"
        title
        |> String.replace(~r/^[A-Z]+\s*[\x{2014}\x{2013}\x{2015}—–:\-]\s*/u, "")
        |> String.trim()

      nil ->
        # Fall back to first line of content, or the type itself
        first_line = clean |> String.split("\n") |> List.first() |> String.trim()

        if first_line != "" do
          first_line |> String.slice(0, 60) |> String.trim()
        else
          String.capitalize(type)
        end
    end
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.trim()
    |> String.replace(~r/\s+/u, "-")
  end
end
