defmodule LunaCore.Roam.Tools do
  @moduledoc """
  The long-term memory tools of the agent. The rules of LunaCore.Roam apply
  here, in code: LUNA changes only her own notes, appends to the notes of
  Coops, and changes no readonly note. A money note taints the conversation,
  and a tainted conversation writes to money notes only.
  """

  alias LunaCore.{Audit, Memory, Roam, Tools}

  @doc "cfg: :root, :memory, :audit, :now (a function)."
  def tools(cfg) do
    [
      %{name: "memory_recall",
        description: "Search the long-term memory (the shared org-roam graph) by title, alias, tag and text. Use it before you answer about a person, a place, a project or a past decision.",
        input_schema: Tools.schema(%{"query" => "Words to find."}),
        run: fn %{"query" => q}, _ -> recall(cfg, q) end},
      %{name: "memory_note",
        description: "Read one note of the long-term memory by its ID, with its links and backlinks.",
        input_schema: Tools.schema(%{"id" => "The ID of the note."}),
        run: fn %{"id" => id}, _ -> read(cfg, id) end},
      %{name: "memory_note_create",
        description: "Make a new note in the long-term memory: one note for one person, place, project, idea or decision. Link to other notes with [[id:ID][Title]]. Search first, so you do not make a second note for one thing.",
        input_schema: Tools.schema(%{"title" => "The title.", "body" => "The text, in org-mode.",
                                     "tags" => ~s(Tags, separated by spaces, for example "person fifo". Can be empty.)}),
        run: fn %{"title" => t, "body" => b, "tags" => tags}, ctx -> create(cfg, t, b, String.split(tags), ctx) end},
      %{name: "memory_note_append",
        description: "Add text to the end of a note. On a note of Coops, the text goes in a new dated section. LUNA cannot change the text of Coops.",
        input_schema: Tools.schema(%{"id" => "The ID of the note.", "text" => "The text, in org-mode."}),
        run: fn %{"id" => id, "text" => text}, ctx -> append(cfg, id, text, ctx) end},
      %{name: "memory_link",
        description: "Link one note to another. The link goes at the end of the first note.",
        input_schema: Tools.schema(%{"from_id" => "The note that gets the link.", "to_id" => "The note that the link goes to.",
                                     "why" => ~s(A few words about the relation, for example "works with".)}),
        run: fn %{"from_id" => f, "to_id" => t, "why" => why}, ctx -> link(cfg, f, t, why, ctx) end}
    ]
  end

  defp fresh_index(cfg) do
    _ = Memory.sync(cfg.memory)
    Roam.index(cfg.root)
  end

  defp taint_of(nodes), do: if(Enum.any?(nodes, &Roam.money?/1), do: "memory read a money note")

  defp ok(text, nil), do: {:ok, text}
  defp ok(text, taint), do: {:ok, text, taint}

  def recall(cfg, query) do
    Audit.write(cfg.audit, "tool", %{name: "memory_recall", query: query})
    index = fresh_index(cfg)

    case Roam.recall(index, query) do
      [] ->
        {:ok, "No note matches."}

      hits ->
        text =
          Enum.map_join(hits, "\n", fn n ->
            snippet = n.body |> String.replace(~r/:PROPERTIES:.*?:END:/s, "") |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)
            "- #{Roam.link(n)} (#{Enum.join(n.tags, " ")}; #{length(Roam.backlinks(index, n.id))} backlinks): #{snippet}"
          end)

        ok(text, taint_of(hits))
    end
  end

  def read(cfg, id) do
    Audit.write(cfg.audit, "tool", %{name: "memory_note", id: id})
    index = fresh_index(cfg)

    case Map.get(index, String.downcase(id)) do
      nil ->
        {:ok, "Error: there is no note #{id}."}

      n ->
        out = for to <- n.links, l = index[to], l != nil, do: Roam.link(l)
        back = for from <- Roam.backlinks(index, n.id), do: Roam.link(index[from])

        text =
          "#{n.title} (#{n.file}, owner: #{n.owner}, tags: #{Enum.join(n.tags, " ")})\n\n#{n.body}\n\n" <>
            "Links: #{Enum.join(out, ", ")}\nBacklinks: #{Enum.join(back, ", ")}"

        ok(text, taint_of([n]))
    end
  end

  def create(cfg, title, body, tags, ctx) do
    Audit.write(cfg.audit, "tool", %{name: "memory_note_create", title: title, tags: tags})
    title = title |> String.replace("\n", " ") |> String.trim()
    tags = tags |> Enum.map(&String.replace(&1, ~r/[^\w@]/u, "")) |> Enum.reject(&(&1 == ""))

    cond do
      title == "" -> {:ok, "Error: a note needs a title."}
      ctx.taint != nil and "money" not in tags -> {:ok, refusal()}
      true -> write_new(cfg, title, body, tags)
    end
  end

  defp write_new(cfg, title, body, tags) do
    now = cfg.now.()
    id = Roam.uuid()
    rel = Path.join(Roam.dir(), Roam.file_name(title, now))
    path = Path.join(cfg.root, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Roam.new_note(id, title, body, tags, now))

    case Memory.commit(cfg.memory, [rel], "LUNA: add the note '#{title}'") do
      :ok ->
        Audit.write(cfg.audit, "roam.created", %{id: id, file: rel})
        {:ok, "Made the note [[id:#{id}][#{title}]] in #{rel}."}

      {:error, message} ->
        {:ok, "Error: the note is written, but the commit failed: #{message}"}
    end
  end

  def append(cfg, id, text, ctx) do
    Audit.write(cfg.audit, "tool", %{name: "memory_note_append", id: id})

    case writable(fresh_index(cfg), id, ctx) do
      {:ok, n} -> write_end(cfg, n, section(cfg, n, String.trim(text) <> "\n"), "LUNA: add to the note '#{n.title}'")
      {:refused, text} -> {:ok, text}
    end
  end

  def link(cfg, from_id, to_id, why, ctx) do
    Audit.write(cfg.audit, "tool", %{name: "memory_link", from: from_id, to: to_id})
    index = fresh_index(cfg)

    with {:ok, from} <- writable(index, from_id, ctx),
         {:ok, to} <- find(index, to_id) do
      why = why |> String.replace("\n", " ") |> String.trim()
      line = "- " <> if(why == "", do: "", else: why <> ": ") <> Roam.link(to) <> "\n"
      write_end(cfg, from, section(cfg, from, line), "LUNA: link '#{from.title}' to '#{to.title}'")
    else
      {:refused, text} -> {:ok, text}
    end
  end

  # The text of Coops does not change: on a note of Coops, LUNA adds a dated section.
  defp section(_cfg, %{owner: :luna}, text), do: "\n" <> text
  defp section(cfg, %{owner: :coops}, text), do: "\n* LUNA, #{Calendar.strftime(cfg.now.(), "[%Y-%m-%d %a]")}\n" <> text

  defp find(index, id) do
    case Map.get(index, String.downcase(id)) do
      nil -> {:refused, "Error: there is no note #{id}."}
      n -> {:ok, n}
    end
  end

  defp writable(index, id, ctx) do
    with {:ok, n} <- find(index, id) do
      cond do
        Roam.readonly?(n) -> {:refused, "Refused: the note \"#{n.title}\" is readonly."}
        ctx.taint != nil and not Roam.money?(n) -> {:refused, refusal()}
        # The end of the file is the end of a file node only.
        n.line != 0 -> {:refused, "Refused: \"#{n.title}\" is a heading in #{n.file}. Append to the file note."}
        true -> {:ok, n}
      end
    end
  end

  defp write_end(cfg, node, addition, message) do
    path = Path.join(cfg.root, node.file)
    File.write!(path, String.trim_trailing(File.read!(path), "\n") <> "\n" <> addition)

    case Memory.commit(cfg.memory, [node.file], message) do
      :ok -> {:ok, "Done: #{Roam.link(node)}."}
      {:error, m} -> {:ok, "Error: the text is written, but the commit failed: #{m}"}
    end
  end

  defp refusal,
    do: "Refused: this conversation read money data. LUNA can write to notes with the tag money only. Start a new conversation with /new."
end
