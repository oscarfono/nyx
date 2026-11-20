defmodule LunaCore.Money.Rules do
  @moduledoc "Reads, applies and adds the category rules in money/categories.org."

  alias LunaCore.Money.OrgTable

  @account ~r/^(assets|liabilities|income|expenses|equity)(:[a-z0-9][a-z0-9-]*)+$/
  @table "Rules"

  @doc "The valid rules as {regex, account}, and a list of problems."
  def load(path) do
    rows = path |> File.read!() |> OrgTable.tables_by_heading() |> Map.get(@table, []) |> Enum.drop(1)

    Enum.reduce(rows, {[], []}, fn
      [pattern, account | _], {rules, problems} when pattern != "" ->
        with {:ok, regex} <- compile(pattern),
             :ok <- check_account(account) do
          {rules ++ [{regex, account}], problems}
        else
          {:error, message} -> {rules, problems ++ [inspect(pattern) <> ": " <> message]}
        end

      _, acc ->
        acc
    end)
  end

  @doc "The account of the first rule that matches, or the unknown account."
  def categorise(description, amount, rules) do
    Enum.find_value(rules, fn {regex, account} -> if Regex.match?(regex, description), do: account end) ||
      if(Decimal.negative?(amount), do: "expenses:unknown", else: "income:unknown")
  end

  @doc "Appends one rule to the table. Returns {:ok, text} or {:error, message}."
  def add(path, pattern, account) do
    with :ok <- if(String.contains?(pattern, ["|", "\n"]), do: {:error, "A pattern cannot contain '|' or a new line. Use two rules."}, else: :ok),
         {:ok, _} <- compile(pattern),
         :ok <- check_account(account) do
      text = File.read!(path)
      text = if String.ends_with?(text, "\n"), do: text, else: text <> "\n"
      File.write!(path, text <> "| #{pattern} | #{account} |\n")
      {:ok, "Added the rule #{inspect(pattern)} -> #{account}."}
    end
  end

  defp compile(pattern) do
    case Regex.compile(pattern, "i") do
      {:ok, regex} -> {:ok, regex}
      {:error, {reason, _}} -> {:error, "The pattern is not a valid regular expression: #{reason}"}
    end
  end

  defp check_account(account) do
    if Regex.match?(@account, account),
      do: :ok,
      else: {:error, "#{inspect(account)} is not a valid account. Use lower case, for example expenses:food:groceries."}
  end
end
