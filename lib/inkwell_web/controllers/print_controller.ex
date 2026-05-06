defmodule InkwellWeb.PrintController do
  use InkwellWeb, :controller

  alias Inkwell.Renderer

  @valid_pagesizes ~w(a4 letter legal)
  @valid_margins ~w(normal narrow none)
  @valid_themes ~w(keep print)

  def show(conn, params) do
    case validate(params) do
      {:ok, opts} -> render_print(conn, opts)
      {:error, :missing_path} -> send_resp(conn, 400, "missing path")
      {:error, :not_absolute} -> send_resp(conn, 400, "path must be absolute")
      {:error, :not_found} -> send_resp(conn, 404, "file not found")
    end
  end

  defp validate(params) do
    with {:ok, path} <- fetch_path(params),
         true <- File.exists?(path) || {:error, :not_found},
         true <- File.regular?(path) || {:error, :not_found} do
      opts = %{
        path: path,
        theme_mode: parse_enum(params["theme"], @valid_themes, "keep"),
        toc: parse_bool(params["toc"], true),
        numbers: parse_bool(params["numbers"], false),
        pagesize: parse_enum(params["pagesize"], @valid_pagesizes, "a4"),
        margins: parse_enum(params["margins"], @valid_margins, "normal"),
        autoprint: params["autoprint"] == "1"
      }

      {:ok, opts}
    else
      {:error, _} = err -> err
      false -> {:error, :not_found}
    end
  end

  defp fetch_path(%{"path" => path}) when is_binary(path) and byte_size(path) > 0 do
    if String.starts_with?(path, "/"), do: {:ok, path}, else: {:error, :not_absolute}
  end

  defp fetch_path(_), do: {:error, :missing_path}

  defp parse_bool("true", _default), do: true
  defp parse_bool("false", _default), do: false
  defp parse_bool(nil, default), do: default
  defp parse_bool(_, default), do: default

  defp parse_enum(value, valid, default) when is_binary(value) do
    if value in valid, do: value, else: default
  end

  defp parse_enum(_, _, default), do: default

  defp render_print(conn, opts) do
    conn = put_format(conn, "html")

    syntax_theme =
      case opts.theme_mode do
        "print" ->
          "onelight"

        "keep" ->
          if(:persistent_term.get(:inkwell_theme, "dark") == "dark",
            do: "onedark",
            else: "onelight"
          )
      end

    {html, headings, _alerts} =
      opts.path
      |> File.read!()
      |> Renderer.render_with_nav(
        base_dir: Path.dirname(opts.path),
        syntax_theme: syntax_theme
      )

    filename = Path.basename(opts.path)

    conn
    |> put_root_layout(false)
    |> put_layout(html: {InkwellWeb.Layouts, :print})
    |> assign(:theme, :persistent_term.get(:inkwell_theme, "dark"))
    |> assign(:theme_mode, opts.theme_mode)
    |> assign(:filename, filename)
    |> assign(:page_size, opts.pagesize)
    |> assign(:page_margin, margin_value(opts.margins))
    |> assign(:page_numbers, opts.numbers)
    |> assign(:autoprint, opts.autoprint)
    |> assign(:article_html, html)
    |> assign(:headings, headings)
    |> assign(:toc, opts.toc)
    |> render(:show)
  end

  defp margin_value("normal"), do: "1in"
  defp margin_value("narrow"), do: "0.5in"
  defp margin_value("none"), do: "0"
end
