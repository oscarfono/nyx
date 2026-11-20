defmodule LunaCore.Telegram do
  @moduledoc "Sends a short nudge to Telegram. A nudge contains no personal data."

  @api "https://api.telegram.org"

  @doc "Sends the text. Does nothing without a token and a chat ID. An error goes to the audit log."
  def nudge(token, chat, text, audit), do: nudge(token, chat, text, audit, @api)

  def nudge(nil, _chat, _text, _audit, _base_url), do: :ok
  def nudge(_token, nil, _text, _audit, _base_url), do: :ok

  def nudge(token, chat, text, audit, base_url) do
    opts = [json: %{chat_id: chat, text: text}, retry: false, receive_timeout: 15_000] ++ LunaCore.Http.options()

    case Req.post(base_url <> "/bot#{token}/sendMessage", opts) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> LunaCore.Audit.write(audit, "telegram.error", %{error: "status #{status}"})
      {:error, exception} -> LunaCore.Audit.write(audit, "telegram.error", %{error: inspect(exception.__struct__)})
    end
  end
end
