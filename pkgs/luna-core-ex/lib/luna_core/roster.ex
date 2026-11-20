defmodule LunaCore.Roster do
  @moduledoc """
  Reads roster.org and gives the swing for any date, in code.

  The table Pattern holds the rule: an anchor date (the first day of an
  on-swing), the on days, the off days, the first shift, and whether the
  shift alternates. A row in the table Swings wins over the pattern for its dates.
  Refer to "Real readouts" in LUNA.org.
  """

  alias LunaCore.Money.OrgTable

  defmodule Swing do
    @moduledoc false
    defstruct [:type, :start, :end, :shift, :site]
  end

  @doc "Parses the text of roster.org. Returns {:ok, roster} or {:error, message}."
  def parse(text) do
    tables = OrgTable.tables_by_heading(text)

    with [row | _] <- OrgTable.records(Map.get(tables, "Pattern", [])),
         {:ok, anchor} <- Date.from_iso8601(row["Anchor"] || ""),
         {on, ""} when on > 0 <- Integer.parse(row["On days"] || ""),
         {off, ""} when off > 0 <- Integer.parse(row["Off days"] || "") do
      {:ok,
       %{
         anchor: anchor,
         on: on,
         off: off,
         first: shift(row["First shift"]) || "days",
         alternate: String.downcase(row["Alternate"] || "") in ["yes", "y", "true"],
         swings: overrides(Map.get(tables, "Swings", []))
       }}
    else
      _ -> {:error, "roster.org has no valid Pattern table. Write the anchor date, the on days and the off days."}
    end
  end

  defp shift(nil), do: nil

  defp shift(text) do
    case String.downcase(String.trim(text)) do
      "nights" <> _ -> "nights"
      "night" <> _ -> "nights"
      "days" <> _ -> "days"
      "day" <> _ -> "days"
      _ -> nil
    end
  end

  defp overrides(rows) do
    for r <- OrgTable.records(rows),
        {:ok, s} <- [Date.from_iso8601(r["Start"] || "")],
        {:ok, e} <- [Date.from_iso8601(r["End"] || "")],
        type <- [String.upcase(r["Type"] || "")],
        type in ["ON", "OFF"] do
      site = r["Site"] || ""
      %Swing{type: if(type == "ON", do: :on, else: :off), start: s, end: e,
             shift: if(type == "ON", do: shift(r["Shift"])), site: if(site == "", do: nil, else: site)}
    end
  end

  @doc "The swing that holds the date."
  def swing_at(roster, date) do
    Enum.find(roster.swings, fn s -> Date.compare(date, s.start) != :lt and Date.compare(date, s.end) != :gt end) ||
      pattern_swing(roster, date)
  end

  defp pattern_swing(r, date) do
    cycle = r.on + r.off
    days = Date.diff(date, r.anchor)
    index = Integer.floor_div(days, cycle)
    cycle_start = Date.add(r.anchor, index * cycle)

    if days - index * cycle < r.on do
      shift = if r.alternate and rem(abs(index), 2) == 1, do: other(r.first), else: r.first
      %Swing{type: :on, start: cycle_start, end: Date.add(cycle_start, r.on - 1), shift: shift}
    else
      start = Date.add(cycle_start, r.on)
      %Swing{type: :off, start: start, end: Date.add(start, r.off - 1)}
    end
  end

  defp other("nights"), do: "days"
  defp other(_), do: "nights"

  @doc "The swing of the date, the day in it, and the next swing."
  def status(roster, date) do
    now = swing_at(roster, date)
    %{swing: now, day: Date.diff(date, now.start) + 1, length: Date.diff(now.end, now.start) + 1,
      next: swing_at(roster, Date.add(now.end, 1)), days_to_next: Date.diff(now.end, date) + 1}
  end

  @doc "The swing of the date and the next n - 1 swings."
  def upcoming(roster, date, n) do
    Enum.reduce(1..n, {[], date}, fn _, {acc, d} -> s = swing_at(roster, d); {acc ++ [s], Date.add(s.end, 1)} end)
    |> elem(0)
  end

  @doc "One sentence for the owner, by voice or in Matrix."
  def sentence(roster, date) do
    st = status(roster, date)
    next = st.next

    current =
      case st.swing.type do
        :off -> "You're on day #{st.day} of #{st.length} of your break."
        :on -> "You're on day #{st.day} of #{st.length} on site, #{st.swing.shift}."
      end

    coming =
      case next.type do
        :on -> "#{String.capitalize(next.shift || "work")} start #{when_text(next.start, st.days_to_next)}."
        :off -> "Your break starts #{when_text(next.start, st.days_to_next)}."
      end

    current <> " " <> coming
  end

  defp when_text(date, 1), do: "tomorrow, #{Calendar.strftime(date, "%A %-d %B")}"
  defp when_text(date, days), do: "#{Calendar.strftime(date, "%A %-d %B")}, in #{days} days"

  @doc "The roster for the page, as plain data."
  def glance(roster, date) do
    st = status(roster, date)

    %{
      type: Atom.to_string(st.swing.type), shift: st.swing.shift, day: st.day, length: st.length,
      days_to_next: st.days_to_next, sentence: sentence(roster, date),
      swings: for(s <- upcoming(roster, date, 4),
                  do: %{type: Atom.to_string(s.type), start: Date.to_iso8601(s.start), end: Date.to_iso8601(s.end), shift: s.shift, site: s.site})
    }
  end
end
