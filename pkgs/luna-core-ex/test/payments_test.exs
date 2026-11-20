defmodule LunaCore.PaymentsTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Approvals, FakeWise, Payments}
  alias LunaCore.Payments.PaymentError

  @moduletag :tmp_dir
  @today ~D[2026-11-23]

  defp settings(mode) do
    Payments.settings(Jason.encode!(%{"mode" => mode, "sandbox" => true, "maxPerPayment" => 100, "maxPerDay" => 150,
      "payees" => %{"landlord" => %{"recipientId" => 42, "currency" => "AUD", "maxPerPayment" => 80}}}))
  end

  defp make(tmp, mode) do
    fake = FakeWise.start()
    {:ok, clock} = Agent.start_link(fn -> ~U[2026-11-23 09:00:00Z] end)
    test = self()

    cfg = %{settings: settings(mode), log: Path.join(tmp, "payments.jsonl"), audit: Path.join(tmp, "audit.jsonl"),
            today: fn -> @today end, now: fn -> Agent.get(clock, & &1) end,
            notify: fn text -> send(test, {:told, text}) end, wise: [token: "token", base_url: fake.url]}

    %{cfg: cfg, fake: fake, clock: clock}
  end

  defp later(clock, hours), do: Agent.update(clock, &DateTime.add(&1, hours * 3600))

  for {payee, amount, currency, message} <- [
        {"stranger", "10", "AUD", "not on the allowlist"},
        {"landlord", "10", "NZD", "takes AUD"},
        {"landlord", "0", "AUD", "more than zero"},
        {"landlord", "90", "AUD", "limit of AUD 80"},
        {"landlord", "abc", "AUD", "not an amount"}
      ] do
    test "the control: #{message}", %{tmp_dir: tmp} do
      %{cfg: cfg} = make(tmp, "draft")
      assert_raise PaymentError, ~r/#{unquote(message)}/, fn ->
        Payments.check(cfg.settings, cfg.log, unquote(payee), unquote(amount), unquote(currency), @today)
      end
    end
  end

  test "off refuses", %{tmp_dir: tmp} do
    %{cfg: cfg} = make(tmp, "off")
    assert_raise PaymentError, ~r/off/, fn -> Payments.check(cfg.settings, cfg.log, "landlord", "10", "AUD", @today) end
  end

  test "a bad mode is refused" do
    assert_raise PaymentError, fn -> Payments.settings(~s({"mode": "yolo"})) end
  end

  test "a dry run calls nothing", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake} = make(tmp, "dry-run")
    assert Payments.request(cfg, "landlord", "50", "AUD", "Rent", "k-1") =~ "Dry run"
    assert FakeWise.calls(fake) == []
  end

  test "a draft makes a transfer and never funds it", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake} = make(tmp, "draft")
    text = Payments.request(cfg, "landlord", "50", "AUD", "Rent", "k-1")
    assert text =~ "Approve in the Wise app"
    assert_received {:told, ^text}
    calls = FakeWise.calls(fake)
    assert {"POST", "/v1/transfers"} in calls
    refute Enum.any?(calls, fn {_, path} -> String.ends_with?(path, "/payments") end)
  end

  test "drafts count toward the day limit", %{tmp_dir: tmp} do
    %{cfg: cfg} = make(tmp, "draft")
    Payments.request(cfg, "landlord", "80", "AUD", "Rent", "k-1")
    assert_raise PaymentError, ~r/limit per day/, fn -> Payments.check(cfg.settings, cfg.log, "landlord", "80", "AUD", @today) end
  end

  test "the watch reports the funding", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake} = make(tmp, "draft")
    Payments.request(cfg, "landlord", "50", "AUD", "Rent", "k-1")
    assert_received {:told, _}
    FakeWise.set_status(fake, "processing")
    Payments.watch_once(cfg)
    assert_received {:told, "You approved" <> _}
    assert Payments.latest(cfg.log)["k-1"]["status"] == "funded"
    Payments.watch_once(cfg)
    refute_received {:told, _}
  end

  test "the watch cancels after 24 hours", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake, clock: clock} = make(tmp, "draft")
    Payments.request(cfg, "landlord", "50", "AUD", "Rent", "k-1")
    later(clock, 23)
    Payments.watch_once(cfg)
    refute {"PUT", "/v1/transfers/555/cancel"} in FakeWise.calls(fake)
    later(clock, 2)
    Payments.watch_once(cfg)
    assert {"PUT", "/v1/transfers/555/cancel"} in FakeWise.calls(fake)
    assert_received {:told, "LUNA cancelled" <> _}
    assert Decimal.eq?(Payments.total_for(cfg.log, @today, "AUD"), 0)
  end

  test "the watch sees a cancel in the app", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake} = make(tmp, "draft")
    Payments.request(cfg, "landlord", "50", "AUD", "Rent", "k-1")
    FakeWise.set_status(fake, "cancelled")
    Payments.watch_once(cfg)
    assert_received {:told, "You cancelled" <> _}
  end

  test "auto mode needs an approval in Matrix", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake} = make(tmp, "auto")
    dir = Path.join(tmp, "approvals")
    File.mkdir_p!(dir)
    {:ok, approvals} = Approvals.start_link(dir: dir, audit: cfg.audit, name: nil)
    [tool] = Payments.tools(cfg, approvals)

    assert {:ok, "Approval request " <> _} =
             tool.run.(%{"payee" => "landlord", "amount" => "50", "currency" => "AUD", "reference" => "Rent", "reason" => "Rent"}, %{taint: nil})

    assert FakeWise.calls(fake) == []
    [item] = Approvals.pending(approvals)
    assert Approvals.approve(approvals, item.id) =~ "Sent AUD 50.00"
    assert {"POST", "/v3/profiles/7/transfers/555/payments"} in FakeWise.calls(fake)
  end

  test "the tool refuses a payment over the limit, and no request goes to Matrix", %{tmp_dir: tmp} do
    %{cfg: cfg, fake: fake} = make(tmp, "auto")
    dir = Path.join(tmp, "approvals")
    File.mkdir_p!(dir)
    {:ok, approvals} = Approvals.start_link(dir: dir, audit: cfg.audit, name: nil)
    [tool] = Payments.tools(cfg, approvals)
    assert {:ok, "Refused: " <> _} = tool.run.(%{"payee" => "landlord", "amount" => "500", "currency" => "AUD", "reference" => "x", "reason" => "x"}, %{taint: nil})
    assert Approvals.pending(approvals) == []
    assert FakeWise.calls(fake) == []
  end

  test "the reference is cleaned" do
    assert Payments.clean_reference("Rent; DROP TABLE <x> 2026-11") == "Rent DROP TABLE x"
  end

  test "the payment key is a version 4 UUID" do
    assert Payments.payment_key() =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end
end
