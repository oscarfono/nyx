defmodule LunaCore.PrivacyTest do
  use ExUnit.Case, async: true

  import LunaCore.Privacy

  for path <- ["money.org", "money/main.journal", "./money/x.org", "briefs/2026.org"] do
    test "#{path} is sensitive", do: assert(sensitive?(unquote(path)))
  end

  for path <- ["notes.org", "travel.org", "moneyish.org", "roster.org"] do
    test "#{path} is not sensitive", do: refute(sensitive?(unquote(path)))
  end

  test "a path that climbs out of the memory is not money" do
    refute sensitive?("money/../notes.org")
  end

  test "the taint blocks writes to clean paths only" do
    assert write_refusal(nil, "notes.org") == nil
    taint = "memory_read money.org"
    assert write_refusal(taint, "notes.org") != nil
    assert write_refusal(taint, "money.org") == nil
  end

  for {text, expected} <- [
        {"Transfer to 062000 12345678", "Transfer to **********5678"},
        {"Card 4111 1111 1111 1111 Woolworths", "Card ************1111 Woolworths"},
        {"BSB 062-000", "BSB **2000"},
        {"Coles 1234.56", "Coles 1234.56"},
        {"Rent 12,345.67", "Rent 12,345.67"},
        {"Date 20/11/2026 ref 99", "Date 20/11/2026 ref 99"},
        {"Short 12345", "Short 12345"},
        {"Wise TRANSFER-123456789", "Wise TRANSFER-*****6789"},
        {"Card xx4111 1111 1111 1111", "Card xx************1111"},
        {"ACCT062000123456", "ACCT********3456"},
        {"Store 1234 Perth", "Store 1234 Perth"}
      ] do
    test "mask #{text}", do: assert(mask_numbers(unquote(text)) == unquote(expected))
  end
end
