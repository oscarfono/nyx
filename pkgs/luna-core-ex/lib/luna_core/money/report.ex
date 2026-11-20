defmodule LunaCore.Money.Report do
  @moduledoc "Runs fixed hledger reports, and returns totals. Code does all the arithmetic."

  NimbleCSV.define(LunaCore.Money.CSV, separator: ",", escape: "\"")
  alias LunaCore.Money.CSV

  @doc "Runs hledger on the main journal. Returns {:ok, output} or {:error, message}."
  def hledger(main, args) do
    case System.find_executable("hledger") do
      nil ->
        {:error, "hledger is not on the PATH."}

      binary ->
        case System.cmd(binary, ["-f", main | args], stderr_to_stdout: true) do
          {out, 0} -> {:ok, out}
          {out, _} -> {:error, String.trim(out)}
        end
    end
  end

  @doc "A map of currency to amount, from a cell like \"AUD 1,234.50, NZD -3\"."
  def parse_amounts(cell) do
    cell
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "0"]))
    |> Enum.reduce(%{}, fn part, acc ->
      case Regex.run(~r/^(?:([A-Z]{3})\s*)?(-?[\d,]*\.?\d+)(?:\s*([A-Z]{3}))?$/, part) do
        nil ->
          acc

        match ->
          currency = Enum.at(match, 1) |> blank_to(Enum.at(match, 3)) |> blank_to("?")
          value = match |> Enum.at(2) |> String.replace(",", "") |> Decimal.new()
          Map.update(acc, currency, value, &Decimal.add(&1, value))
      end
    end)
  end

  # The cell splits at ",", as in the Python core. The journal amounts have no
  # thousands separator, so hledger writes none in its CSV output.

  defp blank_to(nil, other), do: other
  defp blank_to("", other), do: other
  defp blank_to(value, _), do: value

  def balances(main, query, begin_date \\ nil, end_date \\ nil) do
    args =
      ["balance" | query] ++
        ["--flat", "--no-total", "--layout=bare", "-O", "csv"] ++
        if(begin_date, do: ["-b", Date.to_iso8601(begin_date)], else: []) ++
        if(end_date, do: ["-e", Date.to_iso8601(end_date)], else: [])

    with {:ok, out} <- hledger(main, args) do
      rows = CSV.parse_string(out, skip_headers: true)

      result =
        Enum.reduce(rows, %{}, fn
          [account, commodity, amount | _], acc ->
            values = parse_amounts(String.trim("#{commodity} #{amount}"))

            Map.update(acc, account, values, fn old ->
              Map.merge(old, values, fn _k, a, b -> Decimal.add(a, b) end)
            end)

          _, acc ->
            acc
        end)

      {:ok, result}
    end
  end

  def total(by_account) do
    by_account
    |> Map.values()
    |> Enum.reduce(%{}, fn values, acc -> Map.merge(acc, values, fn _k, a, b -> Decimal.add(a, b) end) end)
  end

  @doc "\"AUD 1,234.50, NZD -3.00\", or \"0\". Zero amounts are not shown."
  def money_text(values) do
    shown =
      values
      |> Enum.sort()
      |> Enum.reject(fn {_c, v} -> Decimal.eq?(v, 0) end)
      |> Enum.map(fn {c, v} -> "#{c} #{format(v)}" end)

    if shown == [], do: "0", else: Enum.join(shown, ", ")
  end

  @doc "A number with two decimals and thousands separators, as Python {:,.2f}."
  def format(value) do
    text = value |> Decimal.round(2, :half_even) |> Decimal.to_string(:normal)
    {sign, digits} = if String.starts_with?(text, "-"), do: {"-", String.trim_leading(text, "-")}, else: {"", text}
    [whole | rest] = String.split(digits, ".")
    cents = rest |> List.first("") |> String.pad_trailing(2, "0")

    grouped =
      whole
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign <> grouped <> "." <> cents
  end

  @doc "The last 7 days, today included. The end date is exclusive."
  def week_window(today), do: {Date.add(today, -6), Date.add(today, 1)}
end
