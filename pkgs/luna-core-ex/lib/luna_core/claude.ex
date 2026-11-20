defmodule LunaCore.Claude do
  @moduledoc """
  One request to the Claude Messages API, over HTTP with Req.
  Elixir has no official SDK, so this module sends the documented JSON.
  Refer to "Agent" in LUNA.org.
  """

  @version "2026-10-21"

  @doc """
  Sends the body to POST /v1/messages. Returns {:ok, message} or
  {:error, kind, detail}. kind is :rate_limit, :bad_request, :status or :connection.
  """
  def create(body, opts) do
    request =
      Req.new(
        base_url: Keyword.get(opts, :base_url, "https://api.anthropic.com"),
        url: "/v1/messages",
        json: body,
        headers: [
          {"x-api-key", Keyword.fetch!(opts, :api_key)},
          {"anthropic-version", @version},
          {"anthropic-beta", Enum.join(Keyword.get(opts, :betas, []), ",")}
        ],
        receive_timeout: :timer.minutes(10),
        # Retry 408, 429, 5xx and connection errors, as the SDKs do.
        retry: :transient,
        max_retries: Keyword.get(opts, :max_retries, 2),
        retry_log_level: false
      )
      |> Req.merge(Keyword.get_lazy(opts, :http, &LunaCore.Http.options/0))

    case Req.post(request) do
      {:ok, %{status: 200, body: message}} -> {:ok, message}
      {:ok, %{status: 429}} -> {:error, :rate_limit, nil}
      {:ok, %{status: 400, body: body}} -> {:error, :bad_request, error_message(body)}
      {:ok, %{status: status}} -> {:error, :status, status}
      {:error, exception} -> {:error, :connection, Exception.message(exception)}
    end
  end

  defp error_message(%{"error" => %{"message" => message}}), do: message
  defp error_message(_), do: "no detail"
end
