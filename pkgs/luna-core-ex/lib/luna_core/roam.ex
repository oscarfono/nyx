defmodule LunaCore.Roam do
  @moduledoc """
  The long-term memory: an org-roam graph in roam/ in the memory.
  Coops and LUNA share the graph. Emacs (org-roam) and LUNA read the same files.

  A node is a file or a heading with an :ID: property. A link is
  [[id:UUID]] or [[id:UUID][description]]. The rules (in code, not in the prompt):
    * A note that LUNA made has :CREATED_BY: luna. LUNA can change it.
    * Each other note belongs to Coops. LUNA can only add a section at the end.
    * A note with the tag "readonly" does not change.
    * A note with the tag "money" is money data, for the privacy taint.
  Refer to "Long-term memory" in LUNA.org.
  """

  @dir "roam"
  @link ~r/\[\[id:([0-9A-Fa-f-]{36})(?:\]\[([^\]]*))?\]\]/

  def dir, do: @dir

  @doc "Parses one org file. Returns the nodes: the file node first, then the heading nodes."
  def parse(rel, text) do
    lines = String.split(text, "\n")
    file_tags = file_tags(lines)
    file_title = Enum.find_value(lines, fn l -> match1(~r/^#\+title:\s*(.*)$/i, l) end)
    {file_props, _} = drawer(lines)

    file_node =
      if id = file_props["ID"] do
        [node(id, file_title || Path.basename(rel, ".org"), rel, 0, file_tags, file_props, text)]
      else
        []
      end

    heading_nodes =
      lines
      |> Enum.with_index()
      |> Enum.flat_map(fn {line, i} ->
        case Regex.run(~r/^(\*+)\s+(.*?)(?:\s+(:[\w@#%:]+:))?\s*$/, line) do
          [_, stars | rest] ->
            title = Enum.at(rest, 0)
            tags = rest |> Enum.at(1, "") |> to_string() |> String.split(":", trim: true)
            {props, _} = drawer(Enum.drop(lines, i + 1))

            if id = props["ID"] do
              body = section(lines, i, String.length(stars))
              [node(id, title, rel, i + 1, Enum.uniq(file_tags ++ tags), props, body)]
            else
              []
            end

          nil ->
            []
        end
      end)

    file_node ++ heading_nodes
  end

  defp node(id, title, rel, line, tags, props, body) do
    %{
      id: String.downcase(id),
      title: String.trim(title),
      file: rel,
      line: line,
      tags: tags,
      aliases: aliases(props["ROAM_ALIASES"]),
      owner: if(props["CREATED_BY"] == "luna", do: :luna, else: :coops),
      links: for([_, to | _] <- Regex.scan(@link, body), uniq: true, do: String.downcase(to)),
      body: body
    }
  end

  defp match1(regex, line), do: with([_, v] <- Regex.run(regex, line), do: String.trim(v), else: (_ -> nil))

  defp file_tags(lines) do
    case Enum.find_value(lines, fn l -> match1(~r/^#\+filetags:\s*(.*)$/i, l) end) do
      nil -> []
      tags -> String.split(tags, [":", " "], trim: true)
    end
  end

  # A :PROPERTIES: drawer at the top of the lines (blank lines can come first).
  defp drawer(lines) do
    lines = Enum.drop_while(lines, &(String.trim(&1) == ""))

    case lines do
      [first | rest] ->
        if String.trim(first) == ":PROPERTIES:" do
          {inside, after_} = Enum.split_while(rest, &(String.trim(&1) != ":END:"))

          props =
            for l <- inside, [_, k, v] <- [Regex.run(~r/^\s*:([\w_-]+):\s*(.*?)\s*$/, l)], into: %{},
                do: {String.upcase(k), v}

          {props, Enum.drop(after_, 1)}
        else
          {%{}, lines}
        end

      [] ->
        {%{}, []}
    end
  end

  defp section(lines, i, level) do
    lines
    |> Enum.drop(i)
    |> Enum.with_index()
    |> Enum.take_while(fn {l, n} -> n == 0 or not Regex.match?(~r/^\*{1,#{level}}\s/, l) end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  defp aliases(nil), do: []

  defp aliases(text) do
    Regex.scan(~r/"([^"]+)"|(\S+)/, text) |> Enum.map(fn [_, q | r] -> if q != "", do: q, else: List.first(r) end)
  end

  @doc "Every node in roam/ of the memory root, by ID."
  def index(root) do
    base = Path.join(root, @dir)

    Path.wildcard(Path.join(base, "**/*.org"))
    |> Enum.reject(&(".git" in Path.split(&1)))
    |> Enum.flat_map(fn path -> parse(Path.relative_to(path, root), File.read!(path)) end)
    |> Map.new(&{&1.id, &1})
  end

  @doc "The IDs of the nodes that link to the node."
  def backlinks(index, id), do: for({from, n} <- index, id in n.links, do: from)

  def money?(node), do: "money" in node.tags
  def readonly?(node), do: "readonly" in node.tags

  @doc "Finds nodes for a query. Title, alias and tag matches come first, then the text."
  def recall(index, query, limit \\ 10) do
    words = query |> String.downcase() |> String.split(~r/\W+/u, trim: true)

    index
    |> Map.values()
    |> Enum.map(fn n -> {score(n, String.downcase(query), words), n} end)
    |> Enum.filter(fn {s, _} -> s > 0 end)
    |> Enum.sort_by(fn {s, n} -> {-s, n.title} end)
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 1))
  end

  defp score(n, query, words) do
    title = String.downcase(n.title)
    body = String.downcase(n.body)

    (if title == query, do: 20, else: 0) +
      (if String.contains?(title, query), do: 10, else: 0) +
      Enum.count(n.aliases, &String.contains?(String.downcase(&1), query)) * 8 +
      Enum.count(words, &(&1 in Enum.map(n.tags, fn t -> String.downcase(t) end))) * 5 +
      Enum.sum(for w <- words, do: min(length(String.split(body, w)) - 1, 3))
  end

  @doc "The graph for the page: nodes and links. The money nodes show only the title."
  def graph(index) do
    nodes = for {_, n} <- index, do: %{id: n.id, title: n.title, tags: n.tags, owner: n.owner, file: n.file}
    links = for {from, n} <- index, to <- n.links, Map.has_key?(index, to), do: %{source: from, target: to}
    %{nodes: Enum.sort_by(nodes, & &1.title), links: links}
  end

  @doc "A version 4 UUID, as org-roam makes."
  def uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format("~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b",
      [a, b, Bitwise.band(c, 0x0FFF), Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000), e])
    |> IO.iodata_to_binary()
  end

  @doc "The text of a new LUNA note, in the org-roam file format."
  def new_note(id, title, body, tags, now) do
    tag_line = if tags == [], do: "", else: "#+filetags: :" <> Enum.join(tags, ":") <> ":\n"

    ":PROPERTIES:\n:ID:       #{id}\n:CREATED_BY: luna\n:CREATED: #{Calendar.strftime(now, "[%Y-%m-%d %a %H:%M]")}\n:END:\n" <>
      "#+title: #{title}\n" <> tag_line <> "\n" <> String.trim_trailing(body) <> "\n"
  end

  @doc "The file name of a new note: <timestamp>-<slug>.org, as org-roam makes."
  def file_name(title, now) do
    slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "_") |> String.trim("_")
    Calendar.strftime(now, "%Y%m%d%H%M%S") <> "-" <> String.slice(if(slug == "", do: "note", else: slug), 0, 60) <> ".org"
  end

  @doc "An org link to a node."
  def link(node), do: "[[id:#{node.id}][#{node.title}]]"
end
