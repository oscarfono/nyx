defmodule LunaCore.Matrix.Html do
  @moduledoc """
  A small Markdown renderer for the Matrix messages of LUNA.

  A reply can hold text from a web page, so the renderer escapes all the
  HTML first. Then it adds only a closed set of tags: strong, em, code,
  pre, ul, li, h4 and br. No tag has an attribute, so no attribute can
  carry a script. A table stays as plain text.

  The renderer replaces Earmark, which is retired and had a stored XSS
  advisory (EEF-CVE-2026-48591).
  """

  def render(text) do
    text
    |> String.replace("\r\n", "\n")
    |> split_fences()
    |> Enum.map_join(fn
      {:code, code} -> "<pre><code>" <> escape(code) <> "</code></pre>"
      {:text, part} -> render_lines(part)
    end)
  end

  defp split_fences(text) do
    ~r/```[^\n]*\n(.*?)```/s
    |> Regex.split(text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/\A```[^\n]*\n(.*?)```\z/s, part) do
        [_, code] -> {:code, code}
        nil -> {:text, part}
      end
    end)
  end

  defp render_lines(text) do
    text
    |> String.split("\n")
    |> Enum.chunk_by(&list_item?/1)
    |> Enum.map_join("<br>", fn lines ->
      if list_item?(hd(lines)) do
        "<ul>" <> Enum.map_join(lines, &("<li>" <> inline(strip_bullet(&1)) <> "</li>")) <> "</ul>"
      else
        Enum.map_join(lines, "<br>", &line/1)
      end
    end)
  end

  defp list_item?(line), do: Regex.match?(~r/^\s*[-*+]\s+/, line)
  defp strip_bullet(line), do: Regex.replace(~r/^\s*[-*+]\s+/, line, "")

  defp line(text) do
    case Regex.run(~r/^#+\s+(.*)$/, text) do
      [_, heading] -> "<h4>" <> inline(heading) <> "</h4>"
      nil -> inline(text)
    end
  end

  defp inline(text) do
    text
    |> escape()
    |> then(&Regex.replace(~r/`([^`]+)`/, &1, "<code>\\1</code>"))
    |> then(&Regex.replace(~r/\*\*([^*]+)\*\*/, &1, "<strong>\\1</strong>"))
    |> then(&Regex.replace(~r/(?<![\w*])\*([^*\n]+)\*(?![\w*])/, &1, "<em>\\1</em>"))
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
