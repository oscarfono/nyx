defmodule LunaCore.Money do
  @moduledoc """
  Imports bank files, and gives the agent totals. Code does all arithmetic.

  The config is a map: :root (the memory working copy), :memory (the Memory
  server), :inbox, :audit and :today (a function that returns the date in
  the owner zone). The core API calls summary/1 for the money panel.
  """

  alias LunaCore.{Audit, Memory}
  alias LunaCore.Money.{Import, Plan, Report, Rules}

  defp dir(cfg), do: Path.join(cfg.root, "money")
  defp main(cfg), do: Path.join(dir(cfg), "main.journal")

  # An old main.journal does not include the files that the import writes.
  defp main_problem(cfg) do
    case File.read(main(cfg)) do
      {:error, _} ->
        "money/main.journal does not exist."

      {:ok, text} ->
        if String.contains?(text, "include tx/*.journal"),
          do: nil,
          else:
            "money/main.journal has no line 'include tx/*.journal', so hledger cannot see " <>
              "the imported transactions. Add the line, or copy the seed main.journal."
    end
  end

  @doc "Imports each CSV file in the inbox. Returns counts, not transactions."
  def import_inbox(cfg) do
    _ = Memory.sync(cfg.memory)

    files =
      (Path.wildcard(Path.join(cfg.inbox, "*.csv")) |> Enum.sort()) ++
        (Path.wildcard(Path.join(cfg.inbox, "*.CSV")) |> Enum.sort())

    cond do
      (problem = main_problem(cfg)) != nil -> "No import: #{problem}"
      files == [] -> "The inbox is empty. Send files with make money-upload."
      true -> do_import(cfg, files)
    end
  end

  defp do_import(cfg, files) do
    {rules, problems} = Rules.load(Path.join(dir(cfg), "categories.org"))
    tx_dir = Path.join(dir(cfg), "tx")
    File.mkdir_p!(tx_dir)

    {lines, done, changed, _known} =
      Enum.reduce(files, {[], [], MapSet.new(), Import.existing_ids(tx_dir)}, fn path, {lines, done, changed, known} ->
        name = Path.basename(path)

        case Import.read_file(path) do
          {:error, message} ->
            Audit.write(cfg.audit, "money.import_refused", %{file: name, error: message})
            {lines ++ ["- Kept #{name}: #{message}"], done, changed, known}

          {:ok, profile, account, transactions} ->
            ledger_account = Import.account_for(profile.name, account)
            new = Enum.reject(transactions, &MapSet.member?(known, &1.id))

            entries =
              new
              |> Enum.sort_by(& &1.day, Date)
              |> Enum.map(&{&1.day.year, Import.entry(&1, ledger_account, rules)})

            unknown = Enum.count(entries, fn {_, text} -> String.contains?(text, ":unknown  ") end)

            changed =
              entries
              |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
              |> Enum.reduce(changed, fn {year, texts}, changed ->
                journal = Path.join(tx_dir, "#{year}.journal")
                File.write!(journal, texts, [:append])
                MapSet.put(changed, Path.relative_to(journal, cfg.root))
              end)

            known = Enum.reduce(new, known, &MapSet.put(&2, &1.id))
            Audit.write(cfg.audit, "money.imported", %{file: name, new: length(new), unknown: unknown})

            line = "- #{name}: #{length(new)} new, #{length(transactions) - length(new)} already imported, #{unknown} with no category"
            {lines ++ [line], done ++ [path], changed, known}
        end
      end)

    commit =
      if MapSet.size(changed) > 0,
        do: Memory.commit(cfg.memory, changed |> MapSet.to_list() |> Enum.sort(), "LUNA: import #{length(done)} bank file(s)"),
        else: :ok

    case commit do
      {:error, message} ->
        "The import wrote the journal, but the commit failed: #{message}. The files stay in the inbox."

      :ok ->
        Enum.each(done, &File.rm!/1)
        lines = if problems == [], do: lines, else: lines ++ ["Rules with problems: " <> Enum.join(problems, "; ")]
        "Import:\n" <> Enum.join(lines, "\n")
    end
  end

  @doc "Balances, the spend of the last 7 days, and the safe-to-spend number."
  def summary(cfg) do
    case main_problem(cfg) do
      nil -> do_summary(cfg)
      problem -> "No summary: #{problem}"
    end
  end

  defp do_summary(cfg) do
    today = cfg.today.()
    {begin_date, end_date} = Report.week_window(today)

    with {:ok, held} <- Report.balances(main(cfg), ["^assets", "^liabilities"], nil, Date.add(today, 1)),
         {:ok, spent_by} <- Report.balances(main(cfg), ["^expenses"], begin_date, end_date),
         {:ok, unknown} <- Report.balances(main(cfg), ["^expenses:unknown", "^income:unknown"], Date.add(today, -30), end_date) do
      spent = Report.total(spent_by)
      plan = Plan.load(Path.join(cfg.root, "money.org"))

      rows =
        for {account, values} <- Enum.sort(held), Enum.any?(values, fn {_, v} -> not Decimal.eq?(v, 0) end),
            do: "| #{account} | #{Report.money_text(values)} |"

      safe =
        case Plan.spend_per_week(plan) do
          nil ->
            "Safe to spend per week: not known. " <> Enum.join(plan.missing, "; ")

          weekly ->
            left = if spent["AUD"], do: Decimal.sub(weekly, spent["AUD"]), else: weekly
            "Safe to spend per week: AUD #{Report.format(weekly)}. Left this week: AUD #{Report.format(left)}"
        end

      lines =
        ["**Money**", "", "| Account | Balance |", "|---|---|"] ++
          rows ++ ["", "Spent in the last 7 days: #{Report.money_text(spent)}", safe] ++
          if(unknown == %{}, do: [], else: ["Transactions with no category in 30 days: #{Report.money_text(Report.total(unknown))}. Ask LUNA to show them."])

      Enum.join(lines, "\n")
    else
      {:error, message} -> "hledger failed: #{message}"
    end
  end

  @doc "The safe spend per week and what is left this week, for the page and the quick answers."
  def safe(cfg) do
    with nil <- main_problem(cfg),
         plan = Plan.load(Path.join(cfg.root, "money.org")),
         weekly when weekly != nil <- Plan.spend_per_week(plan),
         {begin_date, end_date} = Report.week_window(cfg.today.()),
         {:ok, spent_by} <- Report.balances(main(cfg), ["^expenses"], begin_date, end_date) do
      spent = Report.total(spent_by)["AUD"] || Decimal.new(0)
      {:ok, %{weekly: weekly, left: Decimal.sub(weekly, spent)}}
    else
      nil -> {:error, "The safe-to-spend number needs the income in money.org."}
      problem when is_binary(problem) -> {:error, "No number: " <> problem}
      {:error, message} -> {:error, "hledger failed: " <> message}
    end
  end

  @doc "The transactions with no category. The descriptions are masked."
  def unknown(cfg, limit \\ 20) do
    today = cfg.today.()
    args = ["register", "^expenses:unknown", "^income:unknown", "-b", Date.to_iso8601(Date.add(today, -90)), "-O", "csv"]

    case Report.hledger(main(cfg), args) do
      {:error, message} ->
        "hledger failed: #{message}"

      {:ok, out} ->
        [header | rows] = LunaCore.Money.CSV.parse_string(out, skip_headers: false)
        col = fn name -> Enum.find_index(header, &(&1 == name)) end
        rows = Enum.take(rows, -limit)

        if rows == [],
          do: "Each transaction has a category.",
          else: Enum.map_join(rows, "\n", fn r -> "- #{Enum.at(r, col.("date"))} #{Enum.at(r, col.("description"))}: #{Enum.at(r, col.("amount"))}" end)
    end
  end

  def add_rule(cfg, pattern, account) do
    _ = Memory.sync(cfg.memory)
    path = Path.join(dir(cfg), "categories.org")

    with {:ok, text} <- Rules.add(path, pattern, account),
         :ok <- Memory.commit(cfg.memory, [Path.relative_to(path, cfg.root)], "LUNA: add the rule #{pattern}") do
      Audit.write(cfg.audit, "money.rule_added", %{pattern: pattern, account: account})
      text <> " The rule applies to the next import."
    else
      {:error, message} -> "Error: " <> message
    end
  end

  @doc "The money tools of the agent. Each tool taints the conversation."
  def tools(cfg) do
    alias LunaCore.Tools

    [
      %{name: "money_summary", description: "Show the balances, the spend of the last 7 days and the safe-to-spend number. Totals only.",
        input_schema: Tools.schema(%{}),
        run: fn _, _ -> Audit.write(cfg.audit, "tool", %{name: "money_summary"}) && {:ok, summary(cfg), "money_summary"} end},
      %{name: "money_import", description: "Import the bank CSV files in the inbox. Return counts only.",
        input_schema: Tools.schema(%{}),
        run: fn _, _ -> Audit.write(cfg.audit, "tool", %{name: "money_import"}) && {:ok, import_inbox(cfg), "money_import"} end},
      %{name: "money_unknown", description: "List recent transactions with no category. Use this only when Coops asks to see them.",
        # Strict tool use needs each property in "required".
        input_schema: %{"type" => "object", "properties" => %{"limit" => %{"type" => "integer", "description" => "The maximum number of transactions, 1 to 50. Use 20 when Coops gives no number."}},
                        "required" => ["limit"], "additionalProperties" => false},
        run: fn input, _ ->
          limit = input |> Map.get("limit", 20) |> max(1) |> min(50)
          Audit.write(cfg.audit, "tool", %{name: "money_unknown", limit: limit})
          {:ok, unknown(cfg, limit), "money_unknown"}
        end},
      %{name: "money_add_rule", description: "Add a category rule. Git records the change.",
        input_schema: Tools.schema(%{"pattern" => "A regular expression that matches the description. The match ignores case.",
                                     "account" => "The hledger account, for example expenses:food:groceries."}),
        run: fn %{"pattern" => p, "account" => a}, _ ->
          Audit.write(cfg.audit, "tool", %{name: "money_add_rule", pattern: p, account: a})
          {:ok, add_rule(cfg, p, a), "money_add_rule"}
        end}
    ]
  end
end
