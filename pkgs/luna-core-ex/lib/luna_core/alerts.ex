defmodule LunaCore.Alerts do
  @moduledoc """
  The alerts of the blue team (B2). luna-sentry watches the journal and
  posts each alert to the core API; this server sends it to the owner room.

  The server sends at most :max alerts in each hour (default 30). The first
  alert over the limit sends one notice; the next alerts go to the audit log only.
  Options: :send (a function of one text), :audit, :max, :name.
  """
  use GenServer

  @window_ms :timer.hours(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Sends one alert. The text is one line from luna-sentry."
  def alert(server \\ __MODULE__, text), do: GenServer.call(server, {:alert, text})

  @impl true
  def init(opts), do: {:ok, %{opts: opts, sent: [], paused: false}}

  @impl true
  def handle_call({:alert, text}, _from, state) do
    now = System.monotonic_time(:millisecond)
    recent = Enum.filter(state.sent, &(now - &1 < @window_ms))
    text = text |> String.replace(~r/[\r\n]+/, " ") |> String.slice(0, 400)
    LunaCore.Audit.write(Keyword.fetch!(state.opts, :audit), "alert", %{text: text})

    cond do
      length(recent) < Keyword.get(state.opts, :max, 30) ->
        Keyword.fetch!(state.opts, :send).("**Blue team:** " <> text)
        {:reply, :sent, %{state | sent: [now | recent], paused: false}}

      not state.paused ->
        Keyword.fetch!(state.opts, :send).("**Blue team:** too many alerts in one hour. The next ones go to the audit log only.")
        {:reply, :paused, %{state | sent: recent, paused: true}}

      true ->
        {:reply, :logged, %{state | sent: recent}}
    end
  end
end
