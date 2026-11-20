defmodule LunaCore.Glance do
  @moduledoc "The readouts of the Console, made in code: the roster and money. ctx is the context of LunaCore.Quick."

  alias LunaCore.{Money, Roster}

  def build(ctx) do
    %{roster: roster(ctx), money: money(ctx)}
  end

  defp roster(ctx) do
    with {:ok, text} <- File.read(Path.join(ctx.root, "roster.org")),
         {:ok, roster} <- Roster.parse(text) do
      Roster.glance(roster, ctx.today.())
    else
      {:error, message} when is_binary(message) -> %{error: message}
      {:error, _} -> %{error: "roster.org is not in the memory yet."}
    end
  end

  defp money(%{money: nil}), do: %{off: true}

  defp money(%{money: cfg}) do
    case Money.safe(cfg) do
      {:ok, %{weekly: w, left: l}} -> %{weekly: Money.Report.format(w), left: Money.Report.format(l)}
      {:error, message} -> %{error: message}
    end
  end
end
