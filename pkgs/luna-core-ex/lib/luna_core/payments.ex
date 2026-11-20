defmodule LunaCore.Payments do
  @moduledoc """
  The Wise float: the limits, the payee allowlist, the Wise client, and the executor.
  Refer to "Build: the Wise float" in LUNA.org.

  WARNING: A payment cannot be undone. Keep the mode "dry-run" until the
  approval flow works for some weeks.

  The config is a map: :settings (from settings/1), :log (the path of
  payments.jsonl), :audit, :today and :now (functions), :notify (a function
  of one text, or nil), and :wise (nil, or [token: _, base_url: _]).
  """

  alias LunaCore.Audit

  @modes ["off", "dry-run", "draft", "auto"]
  @draft_ttl_seconds 24 * 60 * 60
  # Statuses that do not count toward the day total.
  @closed ["failed", "cancelled", "expired"]
  # Wise statuses after funding.
  @funded ["processing", "funds_converted", "outgoing_payment_sent"]

  defmodule PaymentError do
    defexception [:message]
  end

  @doc "The settings from the JSON in the site values. Raises PaymentError for a bad mode."
  def settings(json) do
    data = Jason.decode!(json)
    mode = Map.get(data, "mode", "off")
    if mode not in @modes, do: raise(PaymentError, "The Wise mode #{inspect(mode)} is not one of #{Enum.join(@modes, ", ")}.")

    payees =
      for {name, p} <- Map.get(data, "payees", %{}), into: %{} do
        {name, %{name: name, recipient_id: p["recipientId"], currency: String.upcase(p["currency"]), max_per_payment: dec(p["maxPerPayment"])}}
      end

    %{
      mode: mode,
      sandbox: Map.get(data, "sandbox", true) != false,
      profile_type: data |> Map.get("profileType", "personal") |> String.downcase(),
      max_per_payment: dec(Map.get(data, "maxPerPayment", 100)),
      max_per_day: dec(Map.get(data, "maxPerDay", 200)),
      payees: payees
    }
  end

  defp dec(value) when is_integer(value), do: Decimal.new(value)
  defp dec(value) when is_float(value), do: Decimal.from_float(value)
  defp dec(value) when is_binary(value), do: Decimal.new(value)

  @doc "Wise accepts a short reference. Keeps letters, digits and spaces."
  def clean_reference(text) do
    clean = ~r/[^A-Za-z0-9 ]/ |> Regex.replace(text, "") |> String.trim() |> String.slice(0, 18) |> String.trim()
    if clean == "", do: "LUNA", else: clean
  end

  @doc "The idempotency key for one payment. Wise uses it to refuse a second transfer."
  def payment_key do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    :io_lib.format("~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b", [a, b, Bitwise.band(c, 0x0FFF), Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000), e])
    |> IO.iodata_to_binary()
  end

  # The log of payments. The last record of a payment is its state.

  @doc "The state of each payment. The time stays the time of the first record."
  def latest(path) do
    case File.read(path) do
      {:error, _} ->
        %{}

      {:ok, text} ->
        text
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.reduce(%{}, fn record, state ->
          previous = Map.get(state, record["id"], %{})
          Map.put(state, record["id"], Map.merge(previous, record) |> Map.put("time", previous["time"] || record["time"]))
        end)
    end
  end

  def total_for(path, day, currency) do
    for {_id, r} <- latest(path), r["day"] == Date.to_iso8601(day), r["currency"] == currency, r["status"] not in @closed,
        reduce: Decimal.new(0),
        do: (acc -> Decimal.add(acc, Decimal.new(r["amount"])))
  end

  defp log_write(cfg, record) do
    record = Map.put_new(record, "time", DateTime.to_iso8601(cfg.now.()))
    line = record |> Enum.sort() |> Jason.OrderedObject.new() |> Jason.encode!()
    File.write!(cfg.log, line <> "\n", [:append])
  end

  @doc "Applies each control. Returns {payee, amount}, or raises PaymentError."
  def check(settings, log, payee, amount_text, currency, day) do
    if settings.mode == "off", do: raise(PaymentError, "Payments are off.")

    target =
      Map.get(settings.payees, payee) ||
        raise(PaymentError, "#{inspect(payee)} is not on the allowlist. Allowed: #{allowed(settings)}.")

    amount =
      case Decimal.parse(to_string(amount_text)) do
        {value, ""} -> Decimal.round(value, 2, :half_even)
        _ -> raise(PaymentError, "#{inspect(amount_text)} is not an amount.")
      end

    if String.upcase(currency) != target.currency,
      do: raise(PaymentError, "#{payee} takes #{target.currency}, not #{String.upcase(currency)}.")

    if Decimal.compare(amount, 0) != :gt, do: raise(PaymentError, "The amount must be more than zero.")

    limit = Decimal.min(target.max_per_payment, settings.max_per_payment)

    if Decimal.gt?(amount, limit),
      do: raise(PaymentError, "#{target.currency} #{amount} is more than the limit of #{target.currency} #{limit}.")

    day_total = Decimal.add(total_for(log, day, target.currency), amount)

    if Decimal.gt?(day_total, settings.max_per_day),
      do:
        raise(PaymentError,
          "The day total would be #{target.currency} #{day_total}. The limit per day is #{target.currency} #{settings.max_per_day}.")

    {target, amount}
  end

  defp allowed(settings) do
    case settings.payees |> Map.keys() |> Enum.sort() do
      [] -> "none"
      names -> Enum.join(names, ", ")
    end
  end

  def summary(payee, amount, currency, reference, reason) do
    "Pay **#{payee}** #{currency} #{amount}, reference \"#{reference}\".\nReason: #{reason}\n" <>
      "Auto: after your approval, LUNA makes and funds the transfer."
  end

  # The Wise client: the few API calls that the float uses.

  defp wise(cfg, method, path, body \\ nil) do
    opts = cfg.wise || raise(PaymentError, "No Wise token. Add wise-api-token to the secrets.")
    base = opts[:base_url] || if(cfg.settings.sandbox, do: "https://api.wise-sandbox.com", else: "https://api.wise.com")
    request = [method: method, url: base <> path, headers: [{"authorization", "Bearer " <> opts[:token]}], retry: false, receive_timeout: 30_000]
    request = if body, do: Keyword.put(request, :json, body), else: request

    case Req.request(request) do
      {:ok, %{status: status, body: body}} when status < 400 -> body
      {:ok, %{status: status, body: body}} -> raise(PaymentError, "Wise refused #{method |> to_string() |> String.upcase()} #{path}: HTTP #{status} #{body |> inspect() |> String.slice(0, 200)}")
      {:error, exception} -> raise(PaymentError, "Wise did not answer: #{Exception.message(exception)}")
    end
  end

  defp profile_id(cfg) do
    Enum.find_value(wise(cfg, :get, "/v1/profiles"), fn p -> if String.downcase(to_string(p["type"])) == cfg.settings.profile_type, do: p["id"] end) ||
      raise(PaymentError, "No #{cfg.settings.profile_type} profile on this Wise account.")
  end

  defp send_transfer(cfg, params, fund?) do
    target = Map.fetch!(cfg.settings.payees, params["payee"])
    profile = profile_id(cfg)
    amount = params["amount"] |> Decimal.new() |> Decimal.to_float()
    quote = wise(cfg, :post, "/v3/profiles/#{profile}/quotes", %{"sourceCurrency" => target.currency, "targetCurrency" => target.currency, "targetAmount" => amount})

    transfer =
      wise(cfg, :post, "/v1/transfers", %{
        "targetAccount" => target.recipient_id,
        "quoteUuid" => to_string(quote["id"]),
        "customerTransactionId" => params["key"],
        "details" => %{"reference" => params["reference"]}
      })

    if fund?, do: wise(cfg, :post, "/v3/profiles/#{profile}/transfers/#{transfer["id"]}/payments", %{"type" => "BALANCE"})
    transfer
  end

  defp tell(cfg, text), do: if(cfg[:notify], do: cfg.notify.(text))

  defp record(cfg, key, target, value, day) do
    %{"id" => key, "day" => Date.to_iso8601(day), "payee" => target.name, "amount" => Decimal.to_string(value, :normal),
      "currency" => target.currency, "mode" => cfg.settings.mode, "time" => DateTime.to_iso8601(cfg.now.())}
  end

  @doc "The tool path for dry-run and draft modes. In draft mode the Wise app is the approval."
  def request(cfg, payee, amount, currency, reference, key) do
    day = cfg.today.()
    {target, value} = check(cfg.settings, cfg.log, payee, amount, currency, day)
    params = %{"payee" => target.name, "amount" => Decimal.to_string(value, :normal), "currency" => target.currency, "reference" => clean_reference(reference), "key" => key}
    rec = record(cfg, key, target, value, day)

    if cfg.settings.mode == "dry-run" do
      log_write(cfg, Map.put(rec, "status", "dry-run"))
      "Dry run: LUNA would make a Wise transfer of #{target.currency} #{value} to #{target.name}, for you to approve in the Wise app. LUNA sent nothing."
    else
      transfer =
        try do
          send_transfer(cfg, params, false)
        rescue
          error in PaymentError ->
            log_write(cfg, rec |> Map.put("status", "failed") |> Map.put("error", error.message))
            reraise error, __STACKTRACE__
        end

      log_write(cfg, rec |> Map.put("status", "draft") |> Map.put("transfer_id", transfer["id"]))
      Audit.write(cfg.audit, "payment.draft", %{payee: target.name, amount: Decimal.to_string(value, :normal), transfer_id: transfer["id"]})

      text =
        "**Approve in the Wise app:** transfer #{transfer["id"]}, #{target.currency} #{value} to #{target.name}. " <>
          "To deny, cancel it in the app or do nothing. LUNA cancels it after 24 hours."

      tell(cfg, text)
      text
    end
  end

  @doc "The approval executor, for auto mode. It checks the limits again first."
  def execute(cfg, params) do
    day = cfg.today.()
    {target, value} = check(cfg.settings, cfg.log, params["payee"], params["amount"], params["currency"], day)
    rec = record(cfg, params["key"], target, value, day)

    transfer =
      try do
        send_transfer(cfg, params, true)
      rescue
        error in PaymentError ->
          log_write(cfg, rec |> Map.put("status", "failed") |> Map.put("error", error.message))
          reraise error, __STACKTRACE__
      end

    log_write(cfg, rec |> Map.put("status", "funded") |> Map.put("transfer_id", transfer["id"]))
    Audit.write(cfg.audit, "payment.funded", %{payee: target.name, amount: Decimal.to_string(value, :normal), transfer_id: transfer["id"]})
    "Sent #{target.currency} #{value} to #{target.name}. Wise transfer #{transfer["id"]}."
  end

  @doc "Reports funded drafts. Cancels drafts that wait for more than 24 hours."
  def watch_once(%{wise: nil}), do: :ok

  def watch_once(cfg) do
    for {key, r} <- latest(cfg.log), r["status"] == "draft" do
      id = r["transfer_id"]
      status = to_string(wise(cfg, :get, "/v1/transfers/#{id}")["status"])
      label = "#{r["currency"]} #{r["amount"]} to #{r["payee"]} (transfer #{id})"
      {:ok, created, _} = DateTime.from_iso8601(r["time"])

      cond do
        status in @funded ->
          log_write(cfg, %{"id" => key, "status" => "funded", "wise_status" => status})
          Audit.write(cfg.audit, "payment.funded", %{transfer_id: id})
          tell(cfg, "You approved #{label} in the Wise app. Wise is sending it.")

        status == "cancelled" ->
          log_write(cfg, %{"id" => key, "status" => "cancelled"})
          tell(cfg, "You cancelled #{label}.")

        DateTime.diff(cfg.now.(), created) > @draft_ttl_seconds ->
          wise(cfg, :put, "/v1/transfers/#{id}/cancel")
          log_write(cfg, %{"id" => key, "status" => "expired"})
          Audit.write(cfg.audit, "payment.expired", %{transfer_id: id})
          tell(cfg, "LUNA cancelled #{label}. Nobody funded it in 24 hours.")

        true ->
          :ok
      end
    end

    :ok
  end

  @doc """
  The payment tool. In draft mode the Wise app is the approval; in auto mode,
  Matrix. This function also registers the executor with the approvals.
  """
  def tools(cfg, approvals) do
    :ok = LunaCore.Approvals.register(approvals, "wise_transfer", &execute(cfg, &1))

    [
      %{
        name: "payment_request",
        description:
          "Request a payment from the Wise float to a payee on the allowlist. No money moves now. " <>
            "Coops approves in the Wise app (draft mode) or in Matrix (auto mode).",
        input_schema:
          LunaCore.Tools.schema(%{
            "payee" => "The name of the payee on the allowlist.",
            "amount" => ~s(The amount, for example "45.00".),
            "currency" => ~s(The currency code of the payee, for example "AUD".),
            "reference" => "The payment reference. Wise keeps 18 letters, digits and spaces.",
            "reason" => "Why LUNA asks for this payment, in one sentence."
          }),
        run: fn %{"payee" => payee, "amount" => amount, "currency" => currency, "reference" => reference, "reason" => reason}, _ctx ->
          Audit.write(cfg.audit, "tool", %{name: "payment_request", payee: payee, amount: amount, currency: currency, reason: reason})

          try do
            if cfg.settings.mode in ["dry-run", "draft"] do
              {:ok, request(cfg, payee, amount, currency, reference, payment_key())}
            else
              {target, value} = check(cfg.settings, cfg.log, payee, amount, currency, cfg.today.())
              ref = clean_reference(reference)
              params = %{"payee" => target.name, "amount" => Decimal.to_string(value, :normal), "currency" => target.currency, "reference" => ref, "key" => payment_key()}
              {:ok, item} = LunaCore.Approvals.request(approvals, "wise_transfer", params, summary(target.name, value, target.currency, ref, reason))
              {:ok, "Approval request #{item.id} sent to Coops in Matrix."}
            end
          rescue
            error in PaymentError -> {:ok, "Refused: " <> error.message}
          end
        end
      }
    ]
  end
end
