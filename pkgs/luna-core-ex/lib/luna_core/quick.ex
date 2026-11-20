defmodule LunaCore.Quick do
  @moduledoc """
  Answers fixed questions in code, with no model call (backlog #2):
  the roster ("next swing?") and money ("safe to spend?"). The answer is
  instant, and it works when the Claude API does not.

  The context is a map: :root (the memory), :today (a function), :money
  (nil, or the config of LunaCore.Money).
  """

  alias LunaCore.Roster

  @roster ~r/\b(next swing|my swing|roster|when do i (go back|fly|start|finish)|back to (work|site)|how long (till|until|before) (work|my break|the break|site)|days off left)\b/i
  @money ~r/\b(safe to spend|spending money|how much can i spend)\b/i

  @doc "The answer, or nil when the question is not a fixed question."
  def answer(text, ctx) do
    clean = text |> String.replace_prefix("[voice] ", "") |> String.trim()

    cond do
      String.length(clean) > 120 -> nil
      Regex.match?(@roster, clean) -> roster(ctx)
      Regex.match?(@money, clean) -> money(ctx)
      true -> nil
    end
  end

  defp roster(ctx) do
    with {:ok, text} <- File.read(Path.join(ctx.root, "roster.org")),
         {:ok, roster} <- Roster.parse(text) do
      Roster.sentence(roster, ctx.today.())
    else
      {:error, message} when is_binary(message) -> message
      {:error, _} -> "roster.org is not in the memory yet."
    end
  end

  defp money(%{money: nil}), do: "Money is off, so I have no safe-to-spend number yet."

  defp money(%{money: cfg}) do
    case LunaCore.Money.safe(cfg) do
      {:ok, %{weekly: weekly, left: left}} ->
        "AUD #{LunaCore.Money.Report.format(left)} left of AUD #{LunaCore.Money.Report.format(weekly)} this week."

      {:error, message} ->
        message
    end
  end
end
