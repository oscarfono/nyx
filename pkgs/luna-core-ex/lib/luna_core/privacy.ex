defmodule LunaCore.Privacy do
  @moduledoc """
  Classifies memory paths, and masks account numbers.

  The taint of a conversation is a value in the agent: nil (clean) or the
  reason. A conversation that read money data cannot use the outbound tools,
  and can write money paths only.
  """

  @sensitive_files ["money.org"]
  @sensitive_dirs ["money/", "briefs/"]

  # Tools that send data out of LUNA. A tainted conversation cannot use them.
  @outbound_tools ["web_search", "web_fetch"]

  def outbound_tools, do: @outbound_tools

  def sensitive?(path) do
    clean = path |> Path.expand("/") |> String.trim_leading("/")
    clean in @sensitive_files or String.starts_with?(clean, @sensitive_dirs)
  end

  @doc "Returns the refusal text when a tainted conversation writes a clean path."
  def write_refusal(nil, _path), do: nil

  def write_refusal(_taint, path) do
    if sensitive?(path) do
      nil
    else
      "Error: this conversation read money data. LUNA can write to " <>
        "money.org, money/ or briefs/ only. Start a new conversation with /new."
    end
  end

  # A run of digits with single spaces or dashes between groups. A letter can
  # touch the run, and the mask still applies. A decimal point or a comma next
  # to the run means an amount, so the mask skips it.
  @digit_run ~r/(?<![\d.,])\d(?:[ -]?\d)*(?!\d|[.,]\d)/

  @doc "Masks account and card numbers. Keeps the last four digits. Use it on description text only."
  def mask_numbers(text, min_digits \\ 6) do
    Regex.replace(@digit_run, text, fn run ->
      digits = String.replace(run, ~r/\D/, "")

      if String.length(digits) < min_digits,
        do: run,
        else: String.duplicate("*", String.length(digits) - 4) <> String.slice(digits, -4, 4)
    end)
  end
end
