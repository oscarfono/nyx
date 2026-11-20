defmodule LunaWeb.HomeLive do
  @moduledoc """
  The page: Chat, Approvals, Money and System. Each panel gets its data
  from the core API through LunaWeb.Core. HEEx shows each value as text.
  """
  use Phoenix.LiveView

  alias LunaWeb.Core

  @panels ~w(chat approvals money system)
  @refresh :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        panel: "chat",
        messages: [],
        waiting: false,
        image: nil,
        approvals: [],
        money: nil,
        system: nil,
        notice: nil
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

  def handle_event("decide", %{"id" => id, "action" => action}, socket) do
    notice =
      case Core.decide(id, action) do
        {:ok, result} -> result
        {:error, message} -> message
      end

    {:noreply, socket |> assign(notice: notice) |> load_approvals()}
  end

  @impl true
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

  defp load(socket, key, {:ok, value}), do: assign(socket, key, value)
  defp load(socket, _key, {:error, text}), do: assign(socket, notice: text)

  defp add_message(socket, role, text),
    do: assign(socket, messages: socket.assigns.messages ++ [message(role, text)])

  # Only two roles. A different value from the core becomes "assistant".
  defp message("user", text), do: %{role: "user", text: to_string(text)}
  defp message(_role, text), do: %{role: "assistant", text: to_string(text)}

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
      <h1>LUNA</h1>
      <nav>
        <button
          :for={{panel, label} <- [{"chat", "Chat"}, {"approvals", "Approvals"}, {"money", "Money"}, {"system", "System"}]}
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
