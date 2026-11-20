defmodule LunaCore.Matrix.Bot do
  @moduledoc """
  The Matrix bot: the interface of the owner to LUNA.

  The bot answers the owner only. It does not read encrypted rooms.
  The commands approve, deny and pending go to code, never to the model.
  Each owner message runs in its own task, so an approval works while the
  agent answers a question.

  Options: :homeserver, :user, :owner, :password, :state_dir, :audit,
  :agent ({module, server}), :approvals, :nudge (a function of one text),
  :sync_timeout (ms), :name.
  """
  use GenServer
  require Logger

  alias LunaCore.{Approvals, Audit}
  alias LunaCore.Matrix.Client

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Sends Markdown text to the owner room. Returns false when there is no owner room."
  def send_owner(server \\ __MODULE__, text), do: GenServer.call(server, {:send_owner, text}, :timer.seconds(30))

  @doc "What the bot does with the text of an owner message."
  def route(text) do
    words = String.split(text)

    case Enum.map(words, &String.downcase/1) do
      ["approve", _] -> {:approve, Enum.at(words, 1)}
      ["deny", _] -> {:deny, Enum.at(words, 1)}
      ["pending"] -> :pending
      ["/new" | _] -> :new
      _ -> {:ask, String.trim(text)}
    end
  end

  @doc "The m.room.message content for Markdown text. Refer to LunaCore.Matrix.Html."
  def content(text) do
    %{"msgtype" => "m.text", "body" => text, "format" => "org.matrix.custom.html",
      "formatted_body" => LunaCore.Matrix.Html.render(text)}
  end

  @impl true
  def init(opts) do
    state = %{
      opts: opts,
      token: nil,
      since: nil,
      encrypted: MapSet.new(),
      started_ms: System.system_time(:millisecond),
      relogged: false
    }

    approvals = Keyword.fetch!(opts, :approvals)
    bot = self()
    :ok = Approvals.notify(approvals, fn item -> send(bot, {:approval, item}) end)
    {:ok, state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    with {:ok, state} <- login(state),
         {:ok, body} <- Client.sync(hs(state), state.token, nil, 0) do
      # The first sync skips the old events, but it reads the encrypted rooms and the invites.
      state = %{state | since: body["next_batch"]} |> track_encrypted(body)
      state = join_owner_invites(state, body)
      state = ensure_owner_room(state, body)
      Audit.write(audit(state), "matrix.ready", %{user: opt(state, :user)})
      {:noreply, schedule_sync(state)}
    else
      {:error, reason} ->
        Audit.write(audit(state), "matrix.error", %{step: "start", reason: inspect(reason)})
        {:stop, {:matrix_start, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_owner, text}, _from, state) do
    case owner_room(state) do
      nil -> {:reply, false, state}
      room -> {:reply, deliver(state, room, text) == :ok, state}
    end
  end

  @impl true
  def handle_info({:approval, item}, state) do
    deliver_owner(
      state,
      "**Approval needed** `#{item.id}`\n\n#{item.summary}\n\n" <>
        "Reply `approve #{item.id}` or `deny #{item.id}`. The request expires in 24 hours."
    )

    nudge(state, "LUNA needs your approval. Open Matrix.")
    {:noreply, state}
  end

  def handle_info({ref, result}, %{sync: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = Map.delete(state, :sync)

    case result do
      {:ok, body} ->
        state = %{state | since: body["next_batch"] || state.since, relogged: false} |> track_encrypted(body)
        handle_events(state, body)
        state = join_owner_invites(state, body)
        {:noreply, schedule_sync(state)}

      {:error, 401} when not state.relogged ->
        # The access token is not valid. Log in again, once.
        File.rm(session_file(state))

        case login(%{state | token: nil}) do
          {:ok, state} -> {:noreply, schedule_sync(%{state | relogged: true})}
          {:error, reason} -> {:stop, {:matrix_login, reason}, state}
        end

      {:error, reason} ->
        Audit.write(audit(state), "matrix.error", %{step: "sync", reason: inspect(reason)})
        Process.send_after(self(), :sync, :timer.seconds(10))
        {:noreply, state}
    end
  end

  def handle_info(:sync, state), do: {:noreply, schedule_sync(state)}

  # A message task ended.
  def handle_info({ref, _}, state) when is_reference(ref), do: {:noreply, state}
  def handle_info({:DOWN, _, :process, _, _}, state), do: {:noreply, state}

  defp schedule_sync(state) do
    %{hs: h, token: t, since: s, timeout: timeout} = %{hs: hs(state), token: state.token, since: state.since, timeout: opt(state, :sync_timeout, 30_000)}
    Map.put(state, :sync, Task.async(fn -> Client.sync(h, t, s, timeout) end))
  end

  defp handle_events(state, body) do
    for {room, data} <- get_in(body, ["rooms", "join"]) || %{},
        event <- get_in(data, ["timeline", "events"]) || [] do
      handle_event(state, room, event)
    end
  end

  defp handle_event(state, room, event) do
    sender = event["sender"]
    old? = (event["origin_server_ts"] || 0) < state.started_ms

    cond do
      sender == opt(state, :user) or old? ->
        :ok

      event["type"] == "m.room.encrypted" and sender == opt(state, :owner) ->
        Audit.write(audit(state), "matrix.encrypted_ignored", %{room: room})

        deliver_owner(
          state,
          "You wrote to me in an encrypted room. I cannot read encrypted messages. Write to me here, in this room."
        )

      event["type"] != "m.room.message" or get_in(event, ["content", "msgtype"]) != "m.text" ->
        :ok

      sender != opt(state, :owner) ->
        Audit.write(audit(state), "matrix.message_ignored", %{sender: sender, room: room})

      true ->
        if owner_room(state) != room, do: File.write!(room_file(state), room)
        text = get_in(event, ["content", "body"]) || ""
        # The task can take minutes. The sync goes on.
        Task.start(fn -> answer(state, room, text) end)
    end
  end

  defp answer(state, room, text) do
    approvals = opt(state, :approvals)

    case route(text) do
      {:approve, id} ->
        deliver(state, room, Approvals.approve(approvals, id))

      {:deny, id} ->
        deliver(state, room, Approvals.deny(approvals, id))

      :pending ->
        lines = for item <- Approvals.pending(approvals), do: "- `#{item.id}` #{item.summary}"
        deliver(state, room, if(lines == [], do: "No held actions.", else: Enum.join(lines, "\n")))

      :new ->
        {module, server} = opt(state, :agent)
        module.reset(server)
        deliver(state, room, "New conversation started.")

      {:ask, ""} ->
        :ok

      {:ask, question} ->
        {module, server} = opt(state, :agent)
        Client.typing(hs(state), state.token, room, opt(state, :user), true)

        reply =
          try do
            module.ask(server, question, [])
          after
            Client.typing(hs(state), state.token, room, opt(state, :user), false)
          end

        deliver(state, room, reply)
    end
  end

  defp deliver_owner(state, text) do
    case owner_room(state) do
      nil -> :ok
      room -> deliver(state, room, text)
    end
  end

  # The bot does not write to an encrypted room: it cannot encrypt.
  defp deliver(state, room, text) do
    if MapSet.member?(state.encrypted, room) do
      Audit.write(audit(state), "matrix.send_refused_encrypted", %{room: room})
      :refused
    else
      case Client.send_message(hs(state), state.token, room, content(text)) do
        {:ok, _} -> :ok
        {:error, reason} -> Audit.write(audit(state), "matrix.error", %{step: "send", reason: inspect(reason)})
      end
    end
  end

  defp track_encrypted(state, body) do
    rooms =
      for {room, data} <- get_in(body, ["rooms", "join"]) || %{},
          section <- ["state", "timeline"],
          event <- get_in(data, [section, "events"]) || [],
          event["type"] == "m.room.encryption",
          do: room

    %{state | encrypted: MapSet.union(state.encrypted, MapSet.new(rooms))}
  end

  defp join_owner_invites(state, body) do
    for {room, data} <- get_in(body, ["rooms", "invite"]) || %{} do
      invite =
        Enum.find(get_in(data, ["invite_state", "events"]) || [], fn e ->
          e["type"] == "m.room.member" and e["state_key"] == opt(state, :user) and
            get_in(e, ["content", "membership"]) == "invite"
        end)

      cond do
        invite == nil ->
          :ok

        invite["sender"] == opt(state, :owner) ->
          Client.join(hs(state), state.token, room)
          Audit.write(audit(state), "matrix.joined", %{room: room})

        true ->
          Audit.write(audit(state), "matrix.invite_ignored", %{sender: invite["sender"]})
      end
    end

    state
  end

  # Makes the unencrypted owner room, if LUNA has no owner room yet.
  defp ensure_owner_room(state, body) do
    joined = Map.keys(get_in(body, ["rooms", "join"]) || %{})
    room = owner_room(state)

    if room != nil and room in joined do
      state
    else
      request = %{
        "visibility" => "private",
        "name" => "LUNA",
        "topic" => "Private chat with LUNA. This room is not end-to-end encrypted.",
        # ement.el needs a room ID with a server part. Version 12 has none.
        "room_version" => "11",
        "is_direct" => true,
        "preset" => "trusted_private_chat",
        "invite" => [opt(state, :owner)],
        "creation_content" => %{"m.federate" => false}
      }

      case Client.create_room(hs(state), state.token, request) do
        {:ok, %{"room_id" => id}} ->
          File.write!(room_file(state), id)
          Audit.write(audit(state), "matrix.room_created", %{room: id})

        {:error, reason} ->
          Audit.write(audit(state), "matrix.room_create_failed", %{error: inspect(reason)})
      end

      state
    end
  end

  defp login(state) do
    path = session_file(state)

    with {:ok, text} <- File.read(path),
         {:ok, %{"access_token" => token}} <- Jason.decode(text) do
      {:ok, %{state | token: token}}
    else
      _ ->
        case Client.login(hs(state), opt(state, :user), opt(state, :password)) do
          {:ok, %{"access_token" => token} = body} ->
            session = Map.take(body, ["user_id", "device_id", "access_token"])
            File.write!(path, Jason.encode!(session))
            File.chmod!(path, 0o600)
            {:ok, %{state | token: token}}

          {:ok, _} ->
            {:error, :no_token}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp nudge(state, text) do
    case opt(state, :nudge) do
      nil -> :ok
      fun -> fun.(text)
    end
  end

  defp owner_room(state) do
    case File.read(room_file(state)) do
      {:ok, text} -> if String.trim(text) == "", do: nil, else: String.trim(text)
      {:error, _} -> nil
    end
  end

  defp opt(state, key, default \\ nil), do: Keyword.get(state.opts, key, default)
  defp hs(state), do: opt(state, :homeserver)
  defp audit(state), do: opt(state, :audit)
  defp session_file(state), do: Path.join(opt(state, :state_dir), "matrix-session.json")
  defp room_file(state), do: Path.join(opt(state, :state_dir), "owner-room")
end
