defmodule LunaWeb.HomeLive do
  @moduledoc """
  The page: Chat, Approvals, Money and System. Each panel gets its data
  from the core API through LunaWeb.Core. HEEx shows each value as text.
  """
  use Phoenix.LiveView

  alias LunaWeb.{Core, Voice}

  @panels ~w(chat approvals money memory system)
  # The presence states. "working" comes in stage E4, when the core streams tool events.
  @styles ~w(orb ring)
  @refresh :timer.seconds(30)

  @impl true
  # on_mount checks the owner. mount checks again, because a LiveView bug
  # (EEF-CVE-2026-126334) once let a join skip on_mount.
  def mount(_params, session, socket) do
    if LunaWeb.Owner.owner_session?(session), do: owner_mount(socket), else: {:ok, redirect(socket, to: "/")}
  end

  defp owner_mount(socket) do
    socket =
      assign(socket,
        panel: "chat",
        messages: [],
        waiting: false,
        image: nil,
        approvals: [],
        money: nil,
        system: nil,
        notice: nil,
        presence: "idle",
        presence_style: "orb",
        memory_view: "graph",
        glance: nil,
        memory_count: 0,
        voice: [],
        voice_bytes: 0,
        turn: 0
      )

    if connected?(socket) do
      LunaWeb.Audit.write("web.connect")
      :timer.send_interval(@refresh, :refresh)
      {:ok, socket |> load_history() |> load_approvals() |> load(:system, Core.system()) |> load_memory_count() |> load_glance()}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("show", %{"panel" => panel}, socket) when panel in @panels do
    # The camera preview goes when the chat panel goes. The image goes too.
    socket = assign(socket, panel: panel, notice: nil, image: nil)

    socket =
      case panel do
        "approvals" -> load_approvals(socket)
        "money" -> load(socket, :money, Core.money())
        "system" -> load(socket, :system, Core.system())
        "memory" -> load_memory(socket)
        "chat" -> socket
      end

    {:noreply, socket}
  end

  def handle_event("attach", image, socket) do
    case Core.check_image(image) do
      {:ok, image} -> {:noreply, assign(socket, image: image, notice: nil)}
      {:error, message} -> {:noreply, socket |> assign(image: nil, notice: message) |> push_event("image-cleared", %{})}
    end
  end

  def handle_event("detach", _params, socket), do: {:noreply, assign(socket, image: nil)}

  def handle_event("camera-error", %{"message" => message}, socket) when is_binary(message) do
    {:noreply, assign(socket, notice: "Camera error: " <> String.slice(message, 0, 200))}
  end

  # The reply tells the page to clear the message box. "sent: false" keeps the text.
  def handle_event("send", _params, %{assigns: %{waiting: true}} = socket) do
    {:reply, %{sent: false}, assign(socket, notice: "Wait for the reply to the last message.")}
  end

  def handle_event("send", %{"text" => text}, socket) when is_binary(text) do
    image = socket.assigns.image

    case Core.check_image(image) do
      {:ok, _} when text == "" and is_nil(image) ->
        {:reply, %{sent: false}, socket}

      {:ok, _} ->
        shown = if image, do: String.trim(text) <> "\n[image]", else: String.trim(text)

        socket =
          socket
          |> assign(waiting: true, image: nil, notice: nil)
          |> add_message("user", shown)
          |> push_event("image-cleared", %{})
          |> start_async(:chat, fn -> Core.chat(text, image) end)

        {:reply, %{sent: true}, socket}

      {:error, message} ->
        {:reply, %{sent: false}, assign(socket, notice: message)}
    end
  end

  # Voice. The page sends 16 kHz, 16-bit, mono PCM in base64 chunks while the
  # button is down. A press also stops the voice of LUNA (barge-in).
  def handle_event("voice-start", _params, socket) do
    socket =
      socket
      |> cancel_async(:speak)
      |> assign(presence: "listening", voice: [], voice_bytes: 0, turn: socket.assigns.turn + 1, notice: nil)

    {:noreply, socket}
  end

  def handle_event("voice-chunk", %{"data" => data}, %{assigns: %{presence: "listening"}} = socket)
      when is_binary(data) do
    max = Voice.max_pcm_bytes()

    with {:ok, pcm} <- Base.decode64(data),
         bytes when bytes <= max <- socket.assigns.voice_bytes + byte_size(pcm) do
      {:noreply, assign(socket, voice: [socket.assigns.voice, pcm], voice_bytes: bytes)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("voice-chunk", _params, socket), do: {:noreply, socket}

  def handle_event("voice-stop", _params, %{assigns: %{presence: "listening"}} = socket) do
    pcm = IO.iodata_to_binary(socket.assigns.voice)

    socket =
      socket
      |> assign(presence: "thinking", voice: [], voice_bytes: 0)
      |> start_async(:transcribe, fn -> Voice.transcribe(pcm) end)

    {:noreply, socket}
  end

  def handle_event("voice-stop", _params, socket), do: {:noreply, socket}

  # The page tells the server when the last audio stops.
  def handle_event("voice-done", %{"turn" => turn}, %{assigns: %{turn: turn, presence: "speaking"}} = socket) do
    {:noreply, assign(socket, presence: "idle")}
  end

  def handle_event("voice-done", _params, socket), do: {:noreply, socket}

  def handle_event("presence-style", %{"style" => style}, socket) when style in @styles do
    {:noreply, assign(socket, presence_style: style)}
  end

  def handle_event("presence-style", _params, socket), do: {:noreply, socket}

  # The page draws the graph. The view is "graph" (force) or "map" (mind map).
  def handle_event("memory-view", %{"view" => view}, socket) when view in ["graph", "map"] do
    {:noreply, socket |> assign(memory_view: view) |> push_event("memory-view", %{view: view})}
  end

  def handle_event("memory-view", _params, socket), do: {:noreply, socket}

  # A tap on a note in the graph opens the mind map around it.
  def handle_event("memory-focus", %{"id" => id}, socket) when is_binary(id) do
    {:noreply, socket |> assign(memory_view: "map") |> push_event("memory-view", %{view: "map", focus: id})}
  end

  def handle_event("decide", %{"id" => id, "action" => action}, socket) do
    notice =
      case Core.decide(id, action) do
        {:ok, result} -> result
        {:error, message} -> message
      end

    {:noreply, socket |> assign(notice: notice) |> load_approvals()}
  end

  @impl true
  def handle_async(:transcribe, {:ok, {:ok, text}}, socket) do
    socket =
      socket
      |> add_message("user", "[voice] " <> text)
      |> start_async(:voice_chat, fn -> Voice.ask(text) end)

    {:noreply, socket}
  end

  def handle_async(:transcribe, result, socket), do: {:noreply, voice_error(socket, result)}

  def handle_async(:voice_chat, {:ok, {:ok, reply}}, socket) do
    lv = self()
    turn = socket.assigns.turn
    sentences = Voice.sentences(reply)

    socket =
      socket
      |> assign(presence: "speaking")
      |> add_message("assistant", reply)
      |> load_approvals()
      |> start_async(:speak, fn -> speak(lv, turn, sentences) end)

    {:noreply, socket}
  end

  def handle_async(:voice_chat, result, socket), do: {:noreply, voice_error(socket, result)}

  def handle_async(:speak, {:ok, :ok}, socket), do: {:noreply, socket}
  def handle_async(:speak, {:ok, {:error, message}}, socket), do: {:noreply, voice_error(socket, {:ok, {:error, message}})}
  def handle_async(:speak, {:exit, _}, socket), do: {:noreply, socket}

  def handle_async(:chat, result, socket) do
    text =
      case result do
        {:ok, {:ok, reply}} -> reply
        {:ok, {:error, message}} -> "Error: " <> message
        {:exit, _reason} -> "Error: the request stopped."
      end

    {:noreply, socket |> assign(waiting: false) |> add_message("assistant", text) |> load_approvals()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, socket |> load_approvals() |> load_glance()}

  def handle_info({:voice_audio, turn, audio}, %{assigns: %{turn: turn}} = socket) do
    event = %{turn: turn, rate: audio.rate, data: Base.encode64(audio.pcm)}
    {:noreply, push_event(socket, "voice-audio", event)}
  end

  def handle_info({:voice_end, turn}, %{assigns: %{turn: turn}} = socket) do
    {:noreply, push_event(socket, "voice-end", %{turn: turn})}
  end

  # Audio from an earlier turn. A press of the button stopped that turn.
  def handle_info({:voice_audio, _, _}, socket), do: {:noreply, socket}
  def handle_info({:voice_end, _}, socket), do: {:noreply, socket}

  # Runs in the :speak task. Each sentence goes to the page when it is ready.
  defp speak(lv, turn, sentences) do
    result =
      Enum.reduce_while(sentences, :ok, fn sentence, :ok ->
        case Voice.synthesize(sentence) do
          {:ok, audio} -> send(lv, {:voice_audio, turn, audio}) && {:cont, :ok}
          {:error, message} -> {:halt, {:error, message}}
        end
      end)

    send(lv, {:voice_end, turn})
    result
  end

  defp voice_error(socket, result) do
    message =
      case result do
        {:ok, {:error, message}} -> message
        _ -> "The voice request stopped."
      end

    socket
    |> assign(presence: "error", notice: message)
    |> push_event("voice-error", %{})
  end

  defp load_history(socket) do
    case Core.history() do
      {:ok, messages} ->
        assign(socket, messages: Enum.map(messages, &message(&1["role"], &1["text"])))

      {:error, text} ->
        assign(socket, notice: text)
    end
  end

  defp load_approvals(socket) do
    case Core.approvals() do
      {:ok, items} -> assign(socket, approvals: items)
      {:error, text} -> assign(socket, notice: text)
    end
  end

  defp load_memory(socket) do
    case Core.memory_graph() do
      {:ok, graph} ->
        socket
        |> assign(memory_count: length(graph["nodes"] || []))
        |> push_event("memory-graph", %{nodes: graph["nodes"] || [], links: graph["links"] || [], view: socket.assigns.memory_view})

      {:error, text} ->
        assign(socket, notice: text)
    end
  end

  defp load_glance(socket) do
    case Core.glance() do
      {:ok, glance} -> assign(socket, glance: glance)
      {:error, _} -> socket
    end
  end

  defp load_memory_count(socket) do
    case Core.memory_graph() do
      {:ok, graph} -> assign(socket, memory_count: length(graph["nodes"] || []))
      {:error, _} -> socket
    end
  end

  defp load(socket, key, {:ok, value}), do: assign(socket, key, value)
  defp load(socket, _key, {:error, text}), do: assign(socket, notice: text)

  defp add_message(socket, role, text),
    do: assign(socket, messages: socket.assigns.messages ++ [message(role, text)])

  # Only two roles. A different value from the core becomes "assistant".
  # The core marks a voice message with "[voice] ". The page shows a mark in its place.
  defp message("user", "[voice] " <> text), do: %{role: "user voice", text: text}
  defp message("user", text), do: %{role: "user", text: to_string(text)}
  defp message(_role, text), do: %{role: "assistant", text: to_string(text)}

  defp talk_label("listening"), do: "Listening... release to send"
  defp talk_label("thinking"), do: "LUNA is thinking..."
  defp talk_label("speaking"), do: "Hold to talk (stops LUNA)"
  defp talk_label(_), do: "Hold to talk"

  defp setting(value) when is_binary(value), do: value
  defp setting(value), do: Jason.encode!(value)

  defp event_line(%{"time" => time, "event" => event}) do
    (time |> to_string() |> String.slice(0, 19) |> String.replace("T", " ")) <> "  " <> to_string(event)
  end

  defp event_line(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <header class="bar">
      <div class="brand">
        <span class="wordmark">LUNA</span>
        <span class="status-line">{status_line(@system, @memory_count)}</span>
      </div>
      <div
        id="presence"
        phx-hook="Presence"
        class="presence"
        data-state={@presence}
        data-style={@presence_style}
        role="status"
        aria-label={"LUNA is " <> @presence}
      >
        <div class="orb"></div>
        <svg class="ring" viewBox="0 0 100 100" aria-hidden="true">
          <circle class="ring-track" cx="50" cy="50" r="42" />
          <circle class="ring-arc" cx="50" cy="50" r="42" />
        </svg>
      </div>
      <nav aria-label="Panels">
        <button
          :for={{panel, label} <- [{"chat", "Console"}, {"memory", "Memory"}, {"money", "Money"}, {"approvals", "Approvals"}, {"system", "System"}]}
          phx-click="show"
          phx-value-panel={panel}
          class={if @panel == panel, do: "tab active", else: "tab"}
        >
          {label}<span :if={panel == "approvals" and @approvals != []} class="count">{length(@approvals)}</span>
        </button>
      </nav>
    </header>
    <main class="deck">
      <p :if={@notice} id="notice" class="notice">{@notice}</p>

      <section :if={@panel == "chat"} id="chat" class="console">
        <div class="column readouts" aria-label="Readouts">
          <div class="panel">
            <p class="label">Safe to spend · this week</p>
            <%= case @glance && @glance["money"] do %>
              <% %{"left" => left, "weekly" => weekly} -> %>
                <p class="figure">AUD {left}</p>
                <p class="hint">left of AUD {weekly} this week</p>
              <% %{"error" => error} -> %>
                <p class="figure small">No number yet</p>
                <p class="hint">{error}</p>
              <% _ -> %>
                <p class="figure">Money is off</p>
                <p class="hint">LUNA works this out in code from money.org.</p>
            <% end %>
          </div>
          <div class="panel">
            <p class="label">Roster</p>
            <%= case @glance && @glance["roster"] do %>
              <% %{"type" => type, "day" => day, "length" => length} = roster -> %>
                <p class="figure small">Day {day} of {length} · {roster_title(type, roster["shift"])}</p>
                <div class="roster-strip" aria-hidden="true">
                  <span :for={n <- 1..length} class={if n <= day, do: "done " <> type, else: type}></span>
                </div>
                <p class="hint">{next_swing(roster)}</p>
              <% %{"error" => error} -> %>
                <p class="figure small">Not read</p>
                <p class="hint">{error}</p>
              <% _ -> %>
                <p class="figure small">Not read yet</p>
                <div class="roster-strip" aria-hidden="true"><span :for={_ <- 1..14}></span></div>
            <% end %>
          </div>
          <div class="panel">
            <p class="label">Due · 14 days</p>
            <p class="hint">This needs a due date for each cost in money.org. Ask LUNA to add the dates.</p>
          </div>
        </div>

        <div class="column centre" aria-label="LUNA">
          <div class="instrument" data-state={@presence}>
            <svg viewBox="0 0 360 360" role="img" aria-label={"LUNA is " <> @presence}>
              <circle class="i-outer" cx="180" cy="180" r="170" />
              <circle class="i-ticks" cx="180" cy="180" r="150" />
              <circle class="i-track" cx="180" cy="180" r="120" />
              <circle class="i-arc" cx="180" cy="180" r="120" />
              <circle class="i-core" cx="180" cy="180" r="78" />
              <circle class="i-glow" cx="180" cy="180" r="44" />
              <circle class="i-dot" cx="180" cy="180" r="22" />
              <line class="i-mark" x1="180" y1="6" x2="180" y2="26" />
              <line class="i-mark" x1="180" y1="334" x2="180" y2="354" />
              <line class="i-mark" x1="6" y1="180" x2="26" y2="180" />
              <line class="i-mark" x1="334" y1="180" x2="354" y2="180" />
            </svg>
          </div>
          <p class="state-label">{state_label(@presence)}</p>

          <div id="messages" class="transcript" aria-live="polite">
            <div :for={m <- @messages} class={"msg " <> m.role}>
              <span class="who">{if String.starts_with?(m.role, "user"), do: "You", else: "LUNA"}</span>
              <span class="text">{m.text}</span>
            </div>
            <div :if={@waiting} class="msg assistant wait"><span class="who">LUNA</span><span class="text">Thinking…</span></div>
          </div>

          <button id="talk" phx-hook="Talk" class={"talk " <> @presence} type="button" aria-label="Hold to talk to LUNA">
            {talk_label(@presence)}
          </button>
          <form id="composer" phx-hook="Composer" phx-update="ignore">
            <textarea name="text" rows="2" aria-label="Message LUNA" placeholder="Type to LUNA. Enter sends, Shift+Enter is a new line."></textarea>
            <button type="submit">Send</button>
          </form>
          <div id="camera" phx-hook="Camera" phx-update="ignore">
            <div class="camera-view" hidden>
              <video autoplay playsinline muted></video>
              <div class="row">
                <select aria-label="Camera"></select>
                <button type="button" data-action="snap">Show LUNA</button>
                <button type="button" data-action="close">Close camera</button>
              </div>
            </div>
            <div class="attachment" hidden>
              <img alt="Image for LUNA" />
              <button type="button" data-action="drop">Remove image</button>
            </div>
            <button type="button" class="quiet" data-action="open">Camera</button>
          </div>
        </div>

        <div class="column readouts" aria-label="Activity">
          <div class="panel">
            <p class="label">Task · live</p>
            <p class="hint">Each tool call of LUNA shows here as it runs. It comes with the event stream.</p>
          </div>
          <div class="panel">
            <p class="label">Approvals</p>
            <p class="figure">{length(@approvals)} waiting</p>
            <button :if={@approvals != []} class="quiet" phx-click="show" phx-value-panel="approvals">Open approvals</button>
          </div>
          <div class="panel globe">
            <svg viewBox="0 0 100 100" aria-hidden="true">
              <circle cx="50" cy="50" r="46" /><ellipse cx="50" cy="50" rx="20" ry="46" /><ellipse cx="50" cy="50" rx="38" ry="46" />
              <line x1="4" y1="50" x2="96" y2="50" /><ellipse cx="50" cy="30" rx="40" ry="6" /><ellipse cx="50" cy="70" rx="40" ry="6" />
            </svg>
            <div>
              <p class="label">Globe</p>
              <p class="hint">God's Eye View on luna. It comes later.</p>
            </div>
          </div>
        </div>
      </section>

      <section :if={@panel == "approvals"} id="approvals" class="sheet">
        <p :if={@approvals == []} class="hint">No requests wait for you.</p>
        <div :for={item <- @approvals} class="panel">
          <p class="text">{item["summary"]}</p>
          <p class="hint">{item["id"]} · {item["created"]}</p>
          <div class="row">
            <button phx-click="decide" phx-value-id={item["id"]} phx-value-action="approve">Approve</button>
            <button phx-click="decide" phx-value-id={item["id"]} phx-value-action="deny">Deny</button>
          </div>
        </div>
      </section>

      <section :if={@panel == "money"} id="money" class="sheet">
        <pre class="panel">{@money || "Loading…"}</pre>
      </section>

      <section :if={@panel == "memory"} id="memory" class="sheet">
        <div class="row memory-bar">
          <button phx-click="memory-view" phx-value-view="graph" class={if @memory_view == "graph", do: "tab active", else: "tab"}>Graph</button>
          <button phx-click="memory-view" phx-value-view="map" class={if @memory_view == "map", do: "tab active", else: "tab"}>Mind map</button>
          <span class="hint">{@memory_count} notes</span>
        </div>
        <div id="memory-graph" phx-hook="MemoryGraph" phx-update="ignore" data-view={@memory_view}>
          <input type="search" placeholder="Find a note" aria-label="Find a note" />
          <canvas aria-label="The long-term memory graph"></canvas>
          <p class="memory-title" aria-live="polite"></p>
        </div>
      </section>

      <section :if={@panel == "system"} id="system" class="sheet">
        <div class="row">
          <span class="label">Presence style</span>
          <button
            :for={style <- ["orb", "ring"]}
            phx-click="presence-style"
            phx-value-style={style}
            class={if @presence_style == style, do: "tab active", else: "tab"}
          >
            {String.capitalize(style)}
          </button>
        </div>
        <table :if={@system} class="panel">
          <tr><td class="label">Started</td><td>{@system["started"]}</td></tr>
          <tr><td class="label">Updates</td><td>{@system["update"]}</td></tr>
          <tr><td class="label">Memory</td><td>{@system["memory"]}</td></tr>
          <tr><td class="label">Waiting approvals</td><td>{@system["pending_approvals"]}</td></tr>
          <tr :for={{key, value} <- @system["settings"] || %{}}>
            <td class="label">{key}</td><td>{setting(value)}</td>
          </tr>
        </table>
        <p :if={@system} class="label">Recent events</p>
        <pre :if={@system} class="panel">{Enum.map_join(@system["events"] || [], "\n", &event_line/1)}</pre>
      </section>
    </main>
    """
  end

  # The line under the word mark: the model and the size of the memory.
  defp status_line(nil, count), do: "Shared memory · #{count} notes"

  defp status_line(system, count) do
    model = get_in(system, ["settings", "model"]) || "model"
    "Cloud · #{model} · shared memory · #{count} notes"
  end

  defp roster_title("off", _), do: "break"
  defp roster_title("on", nil), do: "on site"
  defp roster_title("on", shift), do: "on site, " <> shift
  defp roster_title(_, _), do: ""

  # The next swing, from the list of swings: the second one is the next.
  defp next_swing(%{"swings" => [_, next | _], "days_to_next" => days}) do
    what = if next["type"] == "on", do: String.capitalize(next["shift"] || "work") <> " start", else: "Break starts"
    when_ = if days == 1, do: "tomorrow", else: "in #{days} days"
    "#{what} #{when_} · #{next["start"]}"
  end

  defp next_swing(_), do: ""

  defp state_label("listening"), do: "Listening"
  defp state_label("thinking"), do: "Thinking"
  defp state_label("speaking"), do: "Speaking"
  defp state_label("error"), do: "Error"
  defp state_label(_), do: "Standing by"
end
