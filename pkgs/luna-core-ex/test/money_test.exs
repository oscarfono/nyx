defmodule LunaCore.MoneyTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Memory, Money}
  alias LunaCore.Money.{Plan, Rules}

  @moduletag :tmp_dir

  @rules Enum.join([
           "#+TITLE: Categories", "* Rules", "| Pattern | Account |", "|---------+---------|",
           "| woolworths | expenses:food:groceries |", "| transfer to | assets:transfers |",
           "| transfer from | assets:transfers |", "| afterpay | liabilities:afterpay |", ""
         ], "\n")

  @plan Enum.join([
          "* Income", "| Source | Net per pay (AUD) | Pays per year | Net per year |", "| FIFO | 3,000.00 | 26 | |",
          "* Annual costs", "| Category | Item | Per year (AUD) | Due | Bucket |",
          "| Phone | Plan | 600 | Monthly | Bills |", "| Housing | Stays | 15,000 | Each swing | Bills |",
          "* Targets", "| Target | Per year (AUD) |", "| Buffer | 6,000 |", "| Invest | 10,000 |", ""
        ], "\n")

  @files %{
    "commbank--personal.csv" => Enum.join([
      ~s(20/11/2026,"-12.34","WOOLWORTHS 1234 PERTH Card xx4111 1111 1111 1111","+100.00"),
      ~s(21/11/2026,"-500.00","Transfer to xx062000 12345678","-400.00"),
      ~s(21/11/2026,"-9.99","NETFLIX","-409.99")
    ], "\n"),
    "bendigo--savings.csv" => ~s(22/11/2026,"500.00","Transfer from CBA 12345678"\n),
    "up--spending.csv" => "Time,Payee,Description,Total (AUD)\n2026-11-22T09:15:00+08:00,Afterpay,Repayment,-50.00",
    "coopnz--everyday.csv" => "Date,Details,Amount\n19/11/2026,Countdown,-20.50\n",
    "wise--main.csv" => "TransferWise ID,Date,Amount,Currency,Description,Payee Name,Merchant\nTRANSFER-123456789,18-11-2026,-30.00,USD,Card transaction,,GitHub"
  }

  setup %{tmp_dir: tmp} do
    for {k, v} <- [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}, {"GIT_AUTHOR_NAME", "t"},
                   {"GIT_COMMITTER_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@example.com"}, {"GIT_COMMITTER_EMAIL", "t@example.com"}],
        do: System.put_env(k, v)

    root = Path.join(tmp, "memory")
    File.mkdir_p!(Path.join(root, "money/tx"))
    File.write!(Path.join(root, "money/main.journal"), "include accounts.journal\ninclude tx/*.journal\n")
    File.write!(Path.join(root, "money/accounts.journal"), "account assets  ; type: A\n")
    File.write!(Path.join(root, "money/tx/opening.journal"), "; Opening balances.\n")
    File.write!(Path.join(root, "money/categories.org"), @rules)
    File.write!(Path.join(root, "money.org"), @plan)
    {_, 0} = System.cmd("git", ["init", "--quiet", root])
    {_, 0} = System.cmd("git", ["-C", root, "add", "-A"])
    {_, 0} = System.cmd("git", ["-C", root, "commit", "--quiet", "-m", "seed"])
    inbox = Path.join(tmp, "inbox")
    File.mkdir_p!(inbox)
    audit = Path.join(tmp, "audit.jsonl")
    {:ok, memory} = Memory.start_link(root: root, audit: audit, remote: false, name: nil)
    cfg = %{root: root, memory: memory, inbox: inbox, audit: audit, today: fn -> ~D[2026-11-23] end}
    %{cfg: cfg, tmp: tmp}
  end

  defp upload(cfg, names), do: for(n <- names, do: File.write!(Path.join(cfg.inbox, n), @files[n]))
  defp journal(cfg), do: File.read!(Path.join(cfg.root, "money/tx/2026.journal"))

  test "import all profiles", %{cfg: cfg} do
    upload(cfg, Map.keys(@files))
    report = Money.import_inbox(cfg)
    refute report =~ "Kept", report
    text = journal(cfg)
    assert text =~ "expenses:food:groceries  AUD 12.34"
    assert text =~ "assets:bank:commbank:personal  AUD -12.34"
    assert text =~ "liabilities:afterpay  AUD 50.00"
    assert text =~ "assets:bank:coopnz:everyday  NZD -20.50"
    assert text =~ "assets:bank:wise:main  USD -30.00"
    assert File.ls!(cfg.inbox) == []
  end

  test "the import masks numbers", %{cfg: cfg} do
    upload(cfg, ["commbank--personal.csv"])
    Money.import_inbox(cfg)
    text = journal(cfg)
    refute text =~ "4111 1111" or text =~ "12345678"
    assert text =~ "************1111"
  end

  test "a second import adds nothing", %{cfg: cfg} do
    upload(cfg, ["commbank--personal.csv"])
    Money.import_inbox(cfg)
    first = journal(cfg)
    upload(cfg, ["commbank--personal.csv"])
    assert Money.import_inbox(cfg) =~ "0 new, 3 already imported"
    assert journal(cfg) == first
  end

  test "the import commits, and never commits a CSV file", %{cfg: cfg} do
    upload(cfg, ["up--spending.csv"])
    Money.import_inbox(cfg)
    {files, 0} = System.cmd("git", ["-C", cfg.root, "ls-files"])
    assert files =~ "money/tx/2026.journal"
    refute files =~ ".csv"
  end

  test "a wrong header keeps the file", %{cfg: cfg} do
    File.write!(Path.join(cfg.inbox, "up--spending.csv"), "Date,Thing,Value\n2026-11-22,x,1\n")
    report = Money.import_inbox(cfg)
    assert report =~ "Kept up--spending.csv" and report =~ "Send LUNA the header row"
    assert File.exists?(Path.join(cfg.inbox, "up--spending.csv"))
  end

  test "a wrong column count keeps the file", %{cfg: cfg} do
    File.write!(Path.join(cfg.inbox, "commbank--personal.csv"), "20/11/2026,-1.00,X\n")
    assert Money.import_inbox(cfg) =~ "expects 4"
  end

  test "a bad file name is refused", %{cfg: cfg} do
    File.write!(Path.join(cfg.inbox, "statement.csv"), "x\n")
    assert Money.import_inbox(cfg) =~ "<profile>--<account>.csv"
  end

  test "transfers cancel", %{cfg: cfg} do
    upload(cfg, ["commbank--personal.csv", "bendigo--savings.csv"])
    Money.import_inbox(cfg)
    refute Money.summary(cfg) =~ "assets:transfers"
  end

  test "the summary", %{cfg: cfg} do
    upload(cfg, Map.keys(@files))
    Money.import_inbox(cfg)
    text = Money.summary(cfg)
    assert text =~ "assets:bank:commbank:personal | AUD -522.33"
    # 3000 * 26 = 78000; minus 15600 costs, 6000 buffer, 10000 invest; / 52
    assert text =~ "Safe to spend per week: AUD 892.31"
    assert text =~ "no category"
  end

  test "unknown lists the masked transactions", %{cfg: cfg} do
    upload(cfg, ["commbank--personal.csv"])
    Money.import_inbox(cfg)
    text = Money.unknown(cfg)
    assert text =~ "NETFLIX"
    refute text =~ "WOOLWORTHS"
  end

  test "the plan reports missing income", %{tmp: tmp} do
    path = Path.join(tmp, "plan.org")
    File.write!(path, "* Income\n| Source | Net per pay (AUD) | Pays per year | Net per year |\n| FIFO | | | |\n")
    plan = Plan.load(path)
    assert Plan.spend_per_week(plan) == nil and plan.missing != []
  end

  for {pattern, account} <- [{"a|b", "expenses:x"}, {"(", "expenses:x"}, {"ok", "Expenses"}] do
    test "the bad rule #{pattern} #{account} is refused", %{tmp: tmp} do
      path = Path.join(tmp, "categories.org")
      File.write!(path, @rules)
      assert {:error, _} = Rules.add(path, unquote(pattern), unquote(account))
    end
  end

  test "an old main.journal is refused", %{cfg: cfg} do
    File.write!(Path.join(cfg.root, "money/main.journal"), "~ every 4 weeks  pay\n    assets:income  AUD 0\n    income:fifo\n")
    upload(cfg, ["commbank--personal.csv"])
    assert Money.import_inbox(cfg) =~ "include tx/*.journal"
    assert File.exists?(Path.join(cfg.inbox, "commbank--personal.csv"))
  end

  test "a new rule applies to the next import", %{cfg: cfg} do
    assert Money.add_rule(cfg, "netflix", "expenses:subscriptions") =~ "Added"
    upload(cfg, ["commbank--personal.csv"])
    Money.import_inbox(cfg)
    assert journal(cfg) =~ "expenses:subscriptions  AUD 9.99"
  end

  test "the IDs are the same as the IDs of the Python core" do
    # Python: sha256("commbank\x1fpersonal\x1f2026-11-21\x1f-9.99\x1fAUD\x1fNETFLIX\x1f1")[:16]
    key = Enum.join(["commbank", "personal", "2026-11-21", "-9.99", "AUD", "NETFLIX", "1"], <<0x1F>>)
    expected = :crypto.hash(:sha256, key) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    {:ok, _, _, txns} = LunaCore.Money.Import.read_file(write_tmp("commbank--personal.csv", @files["commbank--personal.csv"]))
    assert Enum.at(txns, 2).id == expected
  end

  defp write_tmp(name, text) do
    dir = Path.join(System.tmp_dir!(), "luna-money-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, text)
    path
  end

  test "the money tools mark the taint", %{cfg: cfg} do
    for tool <- Money.tools(cfg), tool.name == "money_summary" do
      assert {:ok, _text, "money_summary"} = tool.run.(%{}, %{taint: nil})
    end
  end
end
