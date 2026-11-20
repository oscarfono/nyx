defmodule LunaCore.Money.Plan do
  @moduledoc "Reads the plan in money.org, and calculates the safe-to-spend number."

  alias LunaCore.Money.OrgTable

  defstruct income: Decimal.new(0), costs: Decimal.new(0), buffer: Decimal.new(0), invest: Decimal.new(0), missing: []

  @doc "The safe spend per week, rounded to cents (half to even), or nil with no income."
  def spend_per_week(%__MODULE__{} = plan) do
    if Decimal.compare(plan.income, 0) == :gt do
      plan.income
      |> Decimal.sub(plan.costs)
      |> Decimal.sub(plan.buffer)
      |> Decimal.sub(plan.invest)
      |> Decimal.div(52)
      |> Decimal.round(2, :half_even)
    end
  end

  @doc "A number from a table cell. Spaces, $, commas and AUD are removed."
  def number(nil), do: nil

  def number(text) do
    clean = Regex.replace(~r/[\s$,]|AUD/, text, "")

    case clean != "" and Decimal.parse(clean) do
      {value, ""} -> value
      _ -> nil
    end
  end

  def load(path) do
    tables = path |> File.read!() |> OrgTable.tables_by_heading()

    income =
      tables
      |> Map.get("Income", [])
      |> OrgTable.records()
      |> Enum.map(fn row ->
        number(row["Net per year"]) ||
          case {number(row["Net per pay (AUD)"]), number(row["Pays per year"])} do
            {nil, _} -> nil
            {_, nil} -> nil
            {pay, pays} -> Decimal.mult(pay, pays)
          end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    costs = tables |> Map.get("Annual costs", []) |> OrgTable.records() |> Enum.map(&number(&1["Per year (AUD)"]))
    known = Enum.reject(costs, &is_nil/1)

    targets =
      for row <- OrgTable.records(Map.get(tables, "Targets", [])),
          value = number(row["Per year (AUD)"]),
          value != nil,
          into: %{},
          do: {String.downcase(row["Target"] || ""), value}

    missing =
      if(Decimal.compare(income, 0) == :gt, do: [], else: ["Income: write the net pay and the pays per year"]) ++
        if(known == [], do: ["Annual costs: write the cost per year in each row"], else: [])

    %__MODULE__{
      income: income,
      costs: Enum.reduce(known, Decimal.new(0), &Decimal.add/2),
      buffer: Map.get(targets, "buffer", Decimal.new(0)),
      invest: Map.get(targets, "invest", Decimal.new(0)),
      missing: missing
    }
  end
end
