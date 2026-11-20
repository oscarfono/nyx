defmodule LunaCore.RoamTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Memory, Roam}
  alias LunaCore.Roam.Tools

  @moduletag :tmp_dir

  @coops_note """
  :PROPERTIES:
  :ID:       065388ea-0e05-40d5-9844-c968fcae26ea
  :ROAM_ALIASES: "Polaris" pol1
  :END:
  #+title: Polaris1
  #+filetags: :project:

  A FIFO site in the Pilbara. Links to [[id:11111111-2222-4333-8444-555555555555][Perth]].

  * Camp
  :PROPERTIES:
  :ID:       aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee
  :END:
  Room 14.
  """

  @perth """
  :PROPERTIES:
  :ID:       11111111-2222-4333-8444-555555555555
  :END:
  #+title: Perth
  #+filetags: :place:readonly:
  The fly-in fly-out airport.
  """

  @money """
  :PROPERTIES:
  :ID:       99999999-2222-4333-8444-555555555555
  :END:
  #+title: Savings plan
  #+filetags: :money:
  Put 10,000 a year in the index fund.
  """

  setup %{tmp_dir: tmp} do
    for {k, v} <- [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}, {"GIT_AUTHOR_NAME", "t"},
                   {"GIT_COMMITTER_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@example.com"}, {"GIT_COMMITTER_EMAIL", "t@example.com"}],
        do: System.put_env(k, v)

    root = Path.join(tmp, "memory")
    File.mkdir_p!(Path.join(root, "roam"))
    File.write!(Path.join(root, "roam/20261117200020-polaris1.org"), @coops_note)
    File.write!(Path.join(root, "roam/20261115210335-perth.org"), @perth)
    File.write!(Path.join(root, "roam/20261115210336-savings.org"), @money)
    {_, 0} = System.cmd("git", ["init", "--quiet", root])
    {_, 0} = System.cmd("git", ["-C", root, "add", "-A"])
    {_, 0} = System.cmd("git", ["-C", root, "commit", "--quiet", "-m", "seed"])
    audit = Path.join(tmp, "audit.jsonl")
    {:ok, memory} = Memory.start_link(root: root, audit: audit, remote: false, name: nil)
    cfg = %{root: root, memory: memory, audit: audit, now: fn -> ~N[2026-11-21 09:30:00] end}
    %{cfg: cfg, root: root}
  end

  defp clean, do: %{taint: nil}
  defp file(root, name), do: File.read!(Path.join([root, "roam", name]))

  test "parse finds the file node, the heading node, the aliases, the tags and the links", %{root: root} do
    index = Roam.index(root)
    polaris = index["065388ea-0e05-40d5-9844-c968fcae26ea"]
    assert polaris.title == "Polaris1"
    assert polaris.aliases == ["Polaris", "pol1"]
    assert polaris.tags == ["project"]
    assert polaris.owner == :coops
    assert polaris.links == ["11111111-2222-4333-8444-555555555555"]
    camp = index["aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"]
    assert camp.title == "Camp" and camp.tags == ["project"] and camp.line > 0
    assert Roam.backlinks(index, "11111111-2222-4333-8444-555555555555") |> Enum.member?(polaris.id)
  end

  test "recall puts a title match first", %{root: root} do
    [first | _] = Roam.recall(Roam.index(root), "perth")
    assert first.title == "Perth"
  end

  test "the graph has the nodes and the links", %{root: root} do
    graph = Roam.graph(Roam.index(root))
    assert length(graph.nodes) == 4
    assert %{source: "065388ea-0e05-40d5-9844-c968fcae26ea", target: "11111111-2222-4333-8444-555555555555"} in graph.links
  end

  test "a new LUNA note has the org-roam format, and a commit", %{cfg: cfg, root: root} do
    {:ok, text} = Tools.create(cfg, "Chiang Mai", "A cheap swing place. Near [[id:11111111-2222-4333-8444-555555555555][Perth]].", ["place", "travel"], clean())
    assert text =~ "Made the note [[id:"
    [new] = Path.wildcard(Path.join(root, "roam/20261121093000-chiang_mai.org"))
    note = File.read!(new)
    assert note =~ ~r/^:PROPERTIES:\n:ID:       [0-9a-f-]{36}\n:CREATED_BY: luna\n/
    assert note =~ "#+title: Chiang Mai\n#+filetags: :place:travel:\n"
    {log, 0} = System.cmd("git", ["-C", root, "log", "--oneline"])
    assert log =~ "add the note 'Chiang Mai'"
    assert Roam.index(root) |> Map.values() |> Enum.find(&(&1.title == "Chiang Mai")) |> Map.get(:owner) == :luna
  end

  test "an append to a note of Coops goes in a dated LUNA section, and the old text stays", %{cfg: cfg, root: root} do
    {:ok, "Done:" <> _} = Tools.append(cfg, "065388ea-0e05-40d5-9844-c968fcae26ea", "The next swing starts on 5 December.", clean())
    text = file(root, "20261117200020-polaris1.org")
    assert String.starts_with?(text, String.trim_trailing(@coops_note, "\n"))
    assert text =~ "* LUNA, [2026-11-21 Sat]\nThe next swing starts on 5 December.\n"
  end

  test "a readonly note does not change", %{cfg: cfg, root: root} do
    assert {:ok, "Refused: " <> _} = Tools.append(cfg, "11111111-2222-4333-8444-555555555555", "x", clean())
    assert {:ok, "Refused: " <> _} = Tools.link(cfg, "11111111-2222-4333-8444-555555555555", "065388ea-0e05-40d5-9844-c968fcae26ea", "", clean())
    assert file(root, "20261115210335-perth.org") == @perth
  end

  test "a heading node takes no append", %{cfg: cfg} do
    assert {:ok, "Refused: " <> _} = Tools.append(cfg, "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "x", clean())
  end

  test "a link goes at the end of the first note", %{cfg: cfg, root: root} do
    {:ok, _} = Tools.create(cfg, "Dan", "A mate at site.", ["person"], clean())
    dan = Roam.index(root) |> Map.values() |> Enum.find(&(&1.title == "Dan"))
    {:ok, "Done:" <> _} = Tools.link(cfg, dan.id, "065388ea-0e05-40d5-9844-c968fcae26ea", "works at", clean())
    assert Roam.index(root)[dan.id].links == ["065388ea-0e05-40d5-9844-c968fcae26ea"]
  end

  test "a money note taints the conversation", %{cfg: cfg} do
    assert {:ok, _, "memory read a money note"} = Tools.read(cfg, "99999999-2222-4333-8444-555555555555")
    assert {:ok, _, _} = Tools.recall(cfg, "index fund")
    assert {:ok, _} = Tools.read(cfg, "065388ea-0e05-40d5-9844-c968fcae26ea")
  end

  test "a tainted conversation writes to money notes only", %{cfg: cfg, root: root} do
    tainted = %{taint: "memory read a money note"}
    assert {:ok, "Refused: this conversation read money data" <> _} = Tools.create(cfg, "Leak", "10,000", ["travel"], tainted)
    assert {:ok, "Refused: this conversation read money data" <> _} = Tools.append(cfg, "065388ea-0e05-40d5-9844-c968fcae26ea", "10,000", tainted)
    assert {:ok, "Done:" <> _} = Tools.append(cfg, "99999999-2222-4333-8444-555555555555", "Checked.", tainted)
    refute file(root, "20261117200020-polaris1.org") =~ "10,000"
  end

  test "the UUID is version 4", do: assert(Roam.uuid() =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
