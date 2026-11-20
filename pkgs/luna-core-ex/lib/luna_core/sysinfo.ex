defmodule LunaCore.Sysinfo do
  @moduledoc "Tells the owner when the nixpkgs on luna is old."

  @version_file "/run/current-system/nixos-version"
  @max_age_days 14

  def nixpkgs_date(version) do
    case Regex.run(~r/\.(\d{4})(\d{2})(\d{2})\./, version) do
      [_, y, m, d] -> Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))
      nil -> nil
    end
  end

  @doc "Returns a warning when nixpkgs is older than 14 days, or nil."
  def update_notice(today, version \\ nil), do: notice(today, version || read_version())

  defp notice(_today, :unreadable), do: "System notice: LUNA cannot read the NixOS version."

  defp notice(today, version) do
    case nixpkgs_date(version) do
      nil -> "System notice: LUNA cannot read a date in the NixOS version #{inspect(version)}."
      built -> age_notice(built, Date.diff(today, built))
    end
  end

  defp age_notice(_built, age) when age <= @max_age_days, do: nil

  defp age_notice(built, age) do
    "**System notice:** luna runs nixpkgs from #{Date.to_iso8601(built)}, #{age} days ago. " <>
      "Security fixes are waiting. In nyx, run `nix flake update`, then `make deploy` in luna/."
  end

  defp read_version do
    case File.read(@version_file) do
      {:ok, text} -> String.trim(text)
      {:error, _} -> :unreadable
    end
  end
end
