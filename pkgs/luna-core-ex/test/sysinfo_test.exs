defmodule LunaCore.SysinfoTest do
  use ExUnit.Case, async: true

  import LunaCore.Sysinfo

  @version "26.11.20261117.0490633"

  test "the nixpkgs date", do: assert(nixpkgs_date(@version) == ~D[2026-11-17])
  test "no notice when recent", do: assert(update_notice(~D[2026-11-30], @version) == nil)

  test "a notice when old" do
    assert update_notice(~D[2026-12-15], @version) =~ "28 days"
  end

  test "a notice when the version has no date" do
    assert update_notice(~D[2026-12-15], "26.11") =~ "cannot read a date"
  end
end
