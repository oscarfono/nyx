defmodule LunaCore.Money.Import do
  @moduledoc "Reads bank CSV files, masks account numbers, and makes hledger entries."

  alias LunaCore.Money.Rules
  alias LunaCore.Privacy

  defmodule Profile do
    @moduledoc false
    defstruct [:name, :currency, :date, :amount, :description, :date_formats, :header,
               columns: nil, currency_column: nil, id_column: nil]
  end

  def profiles do
    %{
    "commbank" => %Profile{name: "commbank", currency: "AUD", date: 0, amount: 1, description: [2], date_formats: ["%d/%m/%Y"], header: false, columns: 4},
    "bendigo" => %Profile{name: "bendigo", currency: "AUD", date: 0, amount: 1, description: [2], date_formats: ["%d/%m/%Y"], header: false, columns: 3},
    "up" => %Profile{name: "up", currency: "AUD", date: "Time", amount: "Total (AUD)", description: ["Payee", "Description"], date_formats: ["%Y-%m-%d"], header: true},
    "coopnz" => %Profile{name: "coopnz", currency: "NZD", date: "Date", amount: "Amount", description: ["Details"], date_formats: ["%d/%m/%Y"], header: true},
    "wise" => %Profile{name: "wise", currency: "AUD", date: "Date", amount: "Amount", description: ["Description", "Payee Name", "Merchant"],
                       date_formats: ["%d-%m-%Y", "%Y-%m-%d"], header: true, currency_column: "Currency", id_column: "TransferWise ID"}
    }
  end

  def account_for(profile, account), do: "assets:bank:#{profile}:#{String.downcase(account)}"

  def profile_for(file_name) do
    case Regex.run(~r/^([a-z]+)--([a-z0-9-]+)\.csv$/i, file_name) do
      nil ->
        {:error, "#{file_name}: use the name <profile>--<account>.csv, for example commbank--personal.csv."}

      [_, profile, account] ->
        case Map.fetch(profiles(), String.downcase(profile)) do
          {:ok, p} -> {:ok, p, String.downcase(account)}
          :error -> {:error, "#{file_name}: no profile #{inspect(String.downcase(profile))}. Profiles: #{profiles() |> Map.keys() |> Enum.sort() |> Enum.join(", ")}."}
        end
    end
  end

  def parse_amount(text) do
    clean = String.trim(text)
    negative = String.starts_with?(clean, "(") and String.ends_with?(clean, ")")
    digits = Regex.replace(~r/[\s$,()A-Za-z]/, clean, "")

    case Decimal.parse(digits) do
      {value, ""} -> {:ok, if(negative, do: Decimal.negate(value), else: value)}
      _ -> {:error, "#{inspect(text)} is not an amount"}
    end
  end

  def parse_day(text, formats) do
    clean = String.trim(text)

    case Regex.run(~r/^(\d{4}-\d{2}-\d{2})/, clean) do
      [_, iso] ->
        Date.from_iso8601(iso) |> either("#{inspect(text)} is not a date")

      nil ->
        Enum.find_value(formats, fn format -> strptime(clean, format) end) ||
          {:error, "#{inspect(text)} is not a date in the format #{Enum.join(formats, " or ")}"}
    end
  end

  defp either({:ok, v}, _), do: {:ok, v}
  defp either(_, message), do: {:error, message}

  # The formats of the profiles only: %d, %m and %Y with "/" or "-".
  defp strptime(text, format) do
    order = Regex.scan(~r/%([dmY])/, format) |> Enum.map(fn [_, f] -> f end)
    pattern = format |> Regex.escape() |> String.replace(["%d", "%m"], "(\\d{1,2})") |> String.replace("%Y", "(\\d{4})")

    with [_ | parts] <- Regex.run(~r/^#{pattern}$/, text),
         values = order |> Enum.zip(Enum.map(parts, &String.to_integer/1)) |> Map.new(),
         {:ok, date} <- Date.new(values["Y"], values["m"], values["d"]) do
      {:ok, date}
    else
      _ -> nil
    end
  end

  def clean_description(parts) do
    text =
      parts
      |> Enum.map(&String.trim(&1 || ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")
      # hledger reads ";" as the start of a comment, and "|" as payee|note.
      |> then(&Regex.replace(~r/[;|]/, &1, ","))
      |> then(&Regex.replace(~r/\s+/, &1, " "))
      |> String.trim()
      |> Privacy.mask_numbers()

    if text == "", do: "(no description)", else: text
  end

  @doc "Returns {:ok, profile, account, transactions} or {:error, message}."
  def read_file(path) do
    name = Path.basename(path)

    with {:ok, profile, account} <- profile_for(name) do
      text = path |> File.read!() |> String.replace_prefix("﻿", "")
      rows = text |> LunaCore.Money.CSV.parse_string(skip_headers: false) |> Enum.reject(fn row -> Enum.all?(row, &(String.trim(&1) == "")) end)

      with :ok <- if(rows == [], do: {:error, "#{name}: the file has no rows."}, else: :ok),
           {:ok, index, body} <- layout(profile, rows, name),
           {:ok, transactions} <- transactions(profile, account, index, body, name) do
        {:ok, profile, account, transactions}
      end
    end
  end

  defp layout(%Profile{header: true} = profile, [header | body], name) do
    names = Enum.map(header, &String.trim/1)
    wanted = [profile.date, profile.amount, profile.currency_column, profile.id_column | profile.description] |> Enum.filter(&is_binary/1)

    case Enum.reject(wanted, &(&1 in names)) do
      [] ->
        {:ok, names |> Enum.with_index() |> Map.new(), body}

      missing ->
        {:error, "#{name}: the header has no column #{Enum.join(missing, ", ")}. The #{profile.name} profile is unverified. Send LUNA the header row."}
    end
  end

  defp layout(profile, rows, name) do
    case Enum.find_index(rows, &(length(&1) != profile.columns)) do
      nil -> {:ok, %{}, rows}
      i -> {:error, "#{name}: row #{i + 1} has #{length(Enum.at(rows, i))} columns. The #{profile.name} profile expects #{profile.columns}."}
    end
  end

  defp cell(_row, nil, _index), do: ""

  defp cell(row, column, index) do
    position = if is_binary(column), do: Map.fetch!(index, column), else: column
    Enum.at(row, position, "")
  end

  defp transactions(profile, account, index, body, name) do
    body
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, [], %{}}, fn {row, n}, {:ok, acc, seen} ->
      with {:ok, day} <- parse_day(cell(row, profile.date, index), profile.date_formats),
           {:ok, amount} <- parse_amount(cell(row, profile.amount, index)) do
        currency = cell(row, profile.currency_column, index) |> String.trim() |> String.upcase()
        currency = if currency == "", do: profile.currency, else: currency
        raw = Enum.map(profile.description, &cell(row, &1, index))
        external = cell(row, profile.id_column, index) |> String.trim()

        {key, seen} =
          if external != "" do
            {[profile.name, account, "id", external], seen}
          else
            base = [profile.name, account, Date.to_iso8601(day), Decimal.to_string(amount, :normal), currency, Enum.join(raw, " ")]
            count = Map.get(seen, base, 0) + 1
            {base ++ [Integer.to_string(count)], Map.put(seen, base, count)}
          end

        id = :crypto.hash(:sha256, Enum.join(key, <<0x1F>>)) |> Base.encode16(case: :lower) |> binary_part(0, 16)
        txn = %{day: day, amount: amount, currency: currency, description: clean_description(raw), id: id}
        {:cont, {:ok, acc ++ [txn], seen}}
      else
        {:error, message} -> {:halt, {:error, "#{name}: data row #{n}: #{message}"}}
      end
    end)
    |> case do
      {:ok, txns, _} -> {:ok, txns}
      error -> error
    end
  end

  def existing_ids(tx_dir) do
    Path.wildcard(Path.join(tx_dir, "*.journal"))
    |> Enum.flat_map(fn f -> Regex.scan(~r/luna-id:([0-9a-f]{16})/, File.read!(f)) |> Enum.map(&Enum.at(&1, 1)) end)
    |> MapSet.new()
  end

  def entry(txn, account, rules) do
    category = Rules.categorise(txn.description, txn.amount, rules)
    amount = Decimal.to_string(txn.amount, :normal)
    opposite = txn.amount |> Decimal.negate() |> Decimal.to_string(:normal)

    "#{Date.to_iso8601(txn.day)} #{txn.description}  ; luna-id:#{txn.id}\n" <>
      "    #{category}  #{txn.currency} #{opposite}\n" <>
      "    #{account}  #{txn.currency} #{amount}\n\n"
  end
end
