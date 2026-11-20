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
        memory_count: 0,
        voice: [],
        voice_bytes: 0,
        turn: 0
      )

    if connected?(socket) do
      LunaWeb.Audit.write("web.connect")
      :timer.send_interval(@refresh, :refresh)
      {:ok, socket |> load_history() |> load_approvals()}
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
  def handle_info(:refresh, socket), do: {:noreply, load_approvals(socket)}

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
    <header>
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
      <h1>LUNA</h1>
      <div class="styles" aria-label="Presence style">
        <button
          :for={style <- ["orb", "ring"]}
          phx-click="presence-style"
          phx-value-style={style}
          class={if @presence_style == style, do: "active"}
        >
          {String.capitalize(style)}
        </button>
      </div>
      <nav>
        <button
          :for={{panel, label} <- [{"chat", "Chat"}, {"approvals", "Approvals"}, {"money", "Money"}, {"memory", "Memory"}, {"system", "System"}]}
          phx-click="show"
          phx-value-panel={panel}
          class={if @panel == panel, do: "active"}
        >
          {label}<span :if={panel == "approvals" and @approvals != []}> ({length(@approvals)})</span>
        </button>
      </nav>
    </header>
    <main>
      <p :if={@notice} id="notice" class="notice">{@notice}</p>

      <section :if={@panel == "chat"} id="chat">
        <div id="messages" aria-live="polite">
          <div :for={m <- @messages} class={"msg " <> m.role}>{m.text}</div>
          <div :if={@waiting} class="msg assistant wait">LUNA is thinking...</div>
        </div>
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
          <button type="button" data-action="open">Camera</button>
        </div>
        <button
          id="talk"
          phx-hook="Talk"
          class={"talk " <> @presence}
          type="button"
          aria-label="Hold to talk to LUNA"
        >
          {talk_label(@presence)}
        </button>
        <form id="composer" phx-hook="Composer" phx-update="ignore">
          <textarea name="text" rows="2" placeholder="Message LUNA. Enter sends, Shift+Enter is a new line."></textarea>
          <button type="submit">Send</button>
        </form>
      </section>

      <section :if={@panel == "approvals"} id="approvals">
        <p :if={@approvals == []} class="muted">No requests wait for you.</p>
        <div :for={item <- @approvals} class="card">
          <div>{item["summary"]}</div>
          <div class="muted">{item["id"]} - {item["created"]}</div>
          <div class="row">
            <button phx-click="decide" phx-value-id={item["id"]} phx-value-action="approve">Approve</button>
            <button phx-click="decide" phx-value-id={item["id"]} phx-value-action="deny">Deny</button>
          </div>
        </div>
      </section>

      <section :if={@panel == "money"} id="money">
        <pre>{@money || "Loading..."}</pre>
      </section>

      <section :if={@panel == "memory"} id="memory">
        <div class="row memory-bar">
          <button phx-click="memory-view" phx-value-view="graph" class={if @memory_view == "graph", do: "active"}>Graph</button>
          <button phx-click="memory-view" phx-value-view="map" class={if @memory_view == "map", do: "active"}>Mind map</button>
          <span class="muted">{@memory_count} notes</span>
        </div>
        <div id="memory-graph" phx-hook="MemoryGraph" phx-update="ignore" data-view={@memory_view}>
          <input type="search" placeholder="Find a note" aria-label="Find a note" />
          <canvas aria-label="The long-term memory graph"></canvas>
          <p class="memory-title" aria-live="polite"></p>
        </div>
      </section>

      <section :if={@panel == "system"} id="system">
        <table :if={@system}>
          <tr><td class="muted">Started</td><td>{@system["started"]}</td></tr>
          <tr><td class="muted">Updates</td><td>{@system["update"]}</td></tr>
          <tr><td class="muted">Memory</td><td>{@system["memory"]}</td></tr>
          <tr><td class="muted">Waiting approvals</td><td>{@system["pending_approvals"]}</td></tr>
          <tr :for={{key, value} <- @system["settings"] || %{}}>
            <td class="muted">{key}</td><td>{setting(value)}</td>
          </tr>
        </table>
        <h3 :if={@system}>Recent events</h3>
        <pre :if={@system}>{Enum.map_join(@system["events"] || [], "\n", &event_line/1)}</pre>
      </section>
    </main>
    """
  end
end
