defmodule LunaCore.RosterTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Quick, Roster}

  @moduletag :tmp_dir

  @roster """
  #+TITLE: Roster
  * Pattern
  | Anchor     | On days | Off days | First shift | Alternate |
  |------------+---------+----------+-------------+-----------|
  | 2026-11-25 |      14 |       14 | nights      | yes       |
  * Swings
  | Start      | End        | Type | Shift  | Site | Fly from | Fly to | Notes |
  |------------+------------+------+--------+------+----------+--------+-------|
  """

  defp roster(extra \\ ""), do: elem(Roster.parse(@roster <> extra), 1)

  # The calendar of Coops on 2026-11-21: off now, nights from 25 Nov, then days.
  test "the calendar of Coops" do
    r = roster()
    assert %{type: :off, start: ~D[2026-11-11], end: ~D[2026-11-24]} = Roster.swing_at(r, ~D[2026-11-21])
    assert %{type: :on, shift: "nights", start: ~D[2026-11-25], end: ~D[2026-12-08]} = Roster.swing_at(r, ~D[2026-11-25])
    assert %{type: :off, start: ~D[2026-12-09], end: ~D[2026-12-22]} = Roster.swing_at(r, ~D[2026-12-15])
    assert %{type: :on, shift: "days", start: ~D[2026-12-23], end: ~D[2027-01-05]} = Roster.swing_at(r, ~D[2026-12-23])
    assert %{type: :on, shift: "nights", start: ~D[2027-01-20]} = Roster.swing_at(r, ~D[2027-01-25])
  end

  test "before the anchor, the pattern goes back too" do
    assert %{type: :off, start: ~D[2026-11-11], end: ~D[2026-11-24]} = Roster.swing_at(roster(), ~D[2026-11-21])
    assert %{type: :on, shift: "days", start: ~D[2026-10-28]} = Roster.swing_at(roster(), ~D[2026-11-01])
  end

  test "the status: the day in the swing and the next swing" do
    st = Roster.status(roster(), ~D[2026-11-21])
    assert st.day == 11 and st.length == 14 and st.days_to_next == 4
    assert st.next.type == :on and st.next.shift == "nights"
  end

  test "the sentence for the owner" do
    assert Roster.sentence(roster(), ~D[2026-11-21]) ==
             "You're on day 11 of 14 of your break. Nights start Wednesday 25 November, in 4 days."
    assert Roster.sentence(roster(), ~D[2026-11-24]) =~ "Nights start tomorrow, Wednesday 25 November."
    assert Roster.sentence(roster(), ~D[2026-11-30]) =~ "You're on day 6 of 14 on site, nights. Your break starts Wednesday 9 December, in 9 days."
  end

  test "a row in Swings wins over the pattern" do
    r = roster("| 2026-12-23 | 2027-01-02 | ON   | days   | Polaris1 |          |        | short swing |\n")
    assert %{type: :on, end: ~D[2027-01-02], site: "Polaris1"} = Roster.swing_at(r, ~D[2026-12-30])
  end

  test "four swings for the page" do
    g = Roster.glance(roster(), ~D[2026-11-21])
    assert Enum.map(g.swings, &{&1.type, &1.start, &1.shift}) ==
             [{"off", "2026-11-11", nil}, {"on", "2026-11-25", "nights"}, {"off", "2026-12-09", nil}, {"on", "2026-12-23", "days"}]
  end

  test "no Pattern table is an error" do
    assert {:error, _} = Roster.parse("* Roster\nnothing")
  end

  test "the quick answers", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "roster.org"), @roster)
    ctx = %{root: tmp, today: fn -> ~D[2026-11-21] end, money: nil}
    assert Quick.answer("[voice] When's my next swing?", ctx) =~ "Nights start Wednesday 25 November"
    assert Quick.answer("how long till work", ctx) =~ "day 11 of 14"
    assert Quick.answer("What's safe to spend?", ctx) =~ "Money is off"
    assert Quick.answer("Write me a poem about the roster of my dreams and also the history of rosters in mining camps since 1900, please, long form", ctx) == nil
    assert Quick.answer("hello", ctx) == nil
  end
end
