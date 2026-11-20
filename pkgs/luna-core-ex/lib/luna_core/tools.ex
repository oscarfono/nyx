defmodule LunaCore.Tools do
  @moduledoc """
  The tools that the agent can use, by tier.

  A client tool is a map: name, description, input_schema and run. run takes
  the input and a context map (:taint) and returns {:ok, text} or
  {:ok, text, taint_reason}. A taint reason marks the conversation.
  """

  alias LunaCore.{Audit, Memory, Privacy}

  # Server tools run at Anthropic. Their results are untrusted text (tier 0).
  # Both tools also send data out, so a tainted conversation loses them.
  def server_tools do
    [
      %{"type" => "web_search_20260209", "name" => "web_search", "max_uses" => 5},
      %{"type" => "web_fetch_20260209", "name" => "web_fetch", "max_uses" => 5}
    ]
  end

  @doc "The memory tools. now is a function that returns the time in the owner zone."
  def memory_tools(memory, audit, now) do
    [
      %{
        name: "memory_files",
        description: "List the files in the LUNA memory.",
        input_schema: schema(%{}),
        run: fn _input, _ctx ->
          Audit.write(audit, "tool", %{name: "memory_files"})

          case Memory.files(memory) do
            [] -> {:ok, "The memory is empty."}
            files -> {:ok, Enum.join(files, "\n")}
          end
        end
      },
      %{
        name: "memory_search",
        description: "Search the LUNA memory for a text. The search ignores case.",
        input_schema: schema(%{"query" => "The text to find."}),
        run: fn %{"query" => query}, _ctx ->
          Audit.write(audit, "tool", %{name: "memory_search", query: query})

          case Memory.search(memory, query) do
            {:error, message} ->
              {:ok, "Error: " <> message}

            {:ok, []} ->
              {:ok, "No match."}

            {:ok, hits} ->
              money = Enum.any?(hits, fn hit -> hit |> String.split(":", parts: 2) |> hd() |> Privacy.sensitive?() end)
              text = Enum.join(hits, "\n")
              if money, do: {:ok, text, "memory_search found money data"}, else: {:ok, text}
          end
        end
      },
      %{
        name: "memory_read",
        description: "Read one file from the LUNA memory.",
        input_schema: schema(%{"path" => ~s(The path relative to the memory root, for example "money.org".)}),
        run: fn %{"path" => path}, _ctx ->
          Audit.write(audit, "tool", %{name: "memory_read", path: path})

          case Memory.read(memory, path) do
            {:error, message} -> {:ok, "Error: " <> message}
            {:ok, text} -> if Privacy.sensitive?(path), do: {:ok, text, "memory_read #{path}"}, else: {:ok, text}
          end
        end
      },
      %{
        name: "memory_append",
        description: "Add one org-mode entry to the end of a memory file. Git records each change.",
        input_schema:
          schema(%{
            "path" => "The path relative to the memory root. The file can be new.",
            "heading" => "The heading of the entry, on one line.",
            "body" => "The body of the entry, in org-mode text."
          }),
        run: fn %{"path" => path, "heading" => heading, "body" => body}, ctx ->
          Audit.write(audit, "tool", %{name: "memory_append", path: path, heading: heading})

          case Privacy.write_refusal(ctx.taint, path) do
            nil ->
              case Memory.append(memory, path, heading, body, now.()) do
                {:ok, text} -> {:ok, text}
                {:error, message} -> {:ok, "Error: " <> message}
              end

            refusal ->
              Audit.write(audit, "tool.refused", %{name: "memory_append", path: path, reason: "taint"})
              {:ok, refusal}
          end
        end
      }
    ]
  end

  @doc "A strict object schema. Each property is a required string."
  def schema(properties) do
    %{
      "type" => "object",
      "properties" => Map.new(properties, fn {k, d} -> {k, %{"type" => "string", "description" => d}} end),
      "required" => properties |> Map.keys() |> Enum.sort(),
      "additionalProperties" => false
    }
  end

  @doc "The definition of a client tool, as the API takes it."
  def definition(tool) do
    %{"name" => tool.name, "description" => tool.description, "input_schema" => tool.input_schema, "strict" => true}
  end
end
