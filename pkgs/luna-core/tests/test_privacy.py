import pytest

from luna_core.privacy import Taint, is_sensitive, mask_numbers, write_refusal


@pytest.mark.parametrize("path", ["money.org", "money/main.journal", "./money/x.org", "briefs/2026.org"])
def test_money_paths_are_sensitive(path):
    assert is_sensitive(path)


@pytest.mark.parametrize("path", ["notes.org", "travel.org", "moneyish.org", "roster.org"])
def test_other_paths_are_not_sensitive(path):
    assert not is_sensitive(path)


def test_taint_blocks_writes_to_clean_paths_only():
    taint = Taint()
    assert write_refusal(taint, "notes.org") is None
    taint.mark("memory_read money.org")
    assert write_refusal(taint, "notes.org") is not None
    assert write_refusal(taint, "money.org") is None
    taint.clear()
    assert write_refusal(taint, "notes.org") is None


@pytest.mark.parametrize(
    "text, expected",
    [
        ("Transfer to 062000 12345678", "Transfer to **********5678"),
        ("Card 4111 1111 1111 1111 Woolworths", "Card ************1111 Woolworths"),
        ("BSB 062-000", "BSB **2000"),
        ("Coles 1234.56", "Coles 1234.56"),
        ("Rent 12,345.67", "Rent 12,345.67"),
        ("Date 20/11/2026 ref 99", "Date 20/11/2026 ref 99"),
        ("Short 12345", "Short 12345"),
        ("Wise TRANSFER-123456789", "Wise TRANSFER-*****6789"),
        ("Card xx4111 1111 1111 1111", "Card xx************1111"),
        ("ACCT062000123456", "ACCT********3456"),
        ("Store 1234 Perth", "Store 1234 Perth"),
    ],
)
def test_mask_numbers(text, expected):
    assert mask_numbers(text) == expected
