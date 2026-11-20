defmodule LunaCore.Money.OrgTable do
  @moduledoc "Reads the tables in an org-mode file, by the heading above each table."

  @doc "The rows of each table under its nearest heading. Rules (|-) are omitted."
  def tables_by_heading(text) do
    {tables, _} =
      text
      |> String.split("\n")
      |> Enum.reduce({%{}, nil}, fn line, {tables, heading} ->
        case Regex.run(~r/^\*+\s+(.*?)\s*$/, line) do
          [_, title] ->
            {tables, title}

          nil ->
            cells = String.trim(line)

            if heading == nil or not String.starts_with?(cells, "|") or String.starts_with?(cells, "|-") do
              {tables, heading}
            else
              row = cells |> String.trim("|") |> String.split("|") |> Enum.map(&String.trim/1)
              {Map.update(tables, heading, [row], &(&1 ++ [row])), heading}
            end
        end
      end)

    tables
  end

  @doc "Uses the first row as the column names."
  def records([]), do: []
  def records([names | rows]), do: Enum.map(rows, fn row -> names |> Enum.zip(row) |> Map.new() end)
end
