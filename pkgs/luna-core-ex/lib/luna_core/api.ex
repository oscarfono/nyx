defmodule LunaCore.Api do
  @moduledoc """
  The core API: chat, approvals, money and system, on a unix socket.
  The Phoenix app is the only client. Refer to "Build: the core API" in LUNA.org.

  The options give the parts of the core:
    * :agent - {module, server}. The module has ask/3 and transcript/1.
    * :approvals - the LunaCore.Approvals server.
    * :audit - the path of the audit log.
    * :money - nil (money is off), or {module, server} with summary/1.
    * :settings - a map for the system panel.
    * :memory_root - the memory working copy, or nil.
    * :started - the start time, as a DateTime.
  """
  use Plug.Router, copy_opts_to_assign: :core

  @image_types ~w(image/jpeg image/png image/webp)
  @max_image_bytes 5 * 1024 * 1024

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason, length: 8 * 1024 * 1024
  plug :dispatch

  get "/api/history" do
    {module, server} = conn.assigns.core[:agent]
    reply(conn, 200, %{messages: module.transcript(server)})
  end

  post "/api/chat" do
    core = conn.assigns.core
    body = conn.body_params
    text = body |> Map.get("text", "") |> to_string() |> String.trim()

    with {:ok, images} <- images(body["image"]),
         :ok <- if(text == "" and images == [], do: {:error, "Write a message."}, else: :ok) do
      voice = body["channel"] == "voice"
      text = if voice, do: "[voice] " <> text, else: text
      LunaCore.Audit.write(core[:audit], "web.chat", %{chars: String.length(text), images: length(images), voice: voice})
      {module, server} = core[:agent]
      prompt = if text == "", do: "What do you see?", else: text
      reply(conn, 200, %{reply: module.ask(server, prompt, images)})
    else
      {:error, message} -> reply(conn, 400, %{error: message})
    end
  end

  get "/api/approvals" do
    items =
      conn.assigns.core[:approvals]
      |> LunaCore.Approvals.pending()
      |> Enum.map(&%{id: &1.id, summary: &1.summary, created: &1.created})

    reply(conn, 200, %{approvals: items})
  end

  post "/api/approvals/:id/:action" do
    core = conn.assigns.core

    result =
      case action do
        "approve" -> {:ok, LunaCore.Approvals.approve(core[:approvals], id)}
        "deny" -> {:ok, LunaCore.Approvals.deny(core[:approvals], id)}
        _ -> :error
      end

    case result do
      {:ok, text} ->
        LunaCore.Audit.write(core[:audit], "web.decision", %{id: id, action: action})
        reply(conn, 200, %{result: text})

      :error ->
        reply(conn, 400, %{error: "Use approve or deny."})
    end
  end

  # The long-term memory graph, for the Memory panel. Titles, tags and links only:
  # the page reads no note text. The text of a money note stays on luna.
  get "/api/memory/graph" do
    case conn.assigns.core[:roam_root] do
      nil -> reply(conn, 200, %{nodes: [], links: []})
      root -> reply(conn, 200, LunaCore.Roam.graph(LunaCore.Roam.index(root)))
    end
  end

  # The readouts of the Console: the roster and money, made in code.
  get "/api/glance" do
    case conn.assigns.core[:glance] do
      nil -> reply(conn, 200, %{roster: nil, money: nil})
      fun -> reply(conn, 200, fun.())
    end
  end

  # An alert from luna-sentry (blue team, B2). The text goes to the owner room.
  post "/api/alert" do
    case {conn.assigns.core[:alerts], conn.body_params["text"]} do
      {nil, _} -> reply(conn, 404, %{error: "No alerts here."})
      {_, text} when not is_binary(text) or text == "" -> reply(conn, 400, %{error: "Send a text."})
      {alerts, text} -> reply(conn, 200, %{result: LunaCore.Alerts.alert(alerts, text)})
    end
  end

  get "/api/money" do
    case conn.assigns.core[:money] do
      nil -> reply(conn, 200, %{text: "Money is off. Refer to 'The gate for phase 2' in LUNA.org."})
      {module, server} -> reply(conn, 200, %{text: module.summary(server)})
    end
  end

  get "/api/system" do
    core = conn.assigns.core

    reply(conn, 200, %{
      started: DateTime.to_iso8601(core[:started]),
      update: LunaCore.Sysinfo.update_notice(Date.utc_today()) || "nixpkgs is less than 14 days old.",
      memory: last_commit(core[:memory_root]),
      settings: core[:settings] || %{},
      pending_approvals: length(LunaCore.Approvals.pending(core[:approvals])),
      events: events(core[:audit])
    })
  end

  match _ do
    reply(conn, 404, %{error: "No such request."})
  end

  defp images(nil), do: {:ok, []}
  defp images(image) when image == %{}, do: {:ok, []}

  defp images(%{} = image) do
    type = to_string(image["media_type"] || "")
    data = to_string(image["data"] || "")

    with :ok <- if(type in @image_types, do: :ok, else: {:error, "LUNA accepts JPEG, PNG or WebP images."}),
         {:ok, bytes} <- decode(data),
         :ok <- if(byte_size(bytes) <= @max_image_bytes, do: :ok, else: {:error, "The image is more than 5 MB."}) do
      {:ok, [{type, data}]}
    end
  end

  defp images(_), do: {:error, "The image is not valid."}

  defp decode(data) do
    case Base.decode64(data) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, "The image data is not valid base64."}
    end
  end

  defp last_commit(nil), do: ""

  defp last_commit(root) do
    case System.cmd("git", ["-C", root, "log", "-1", "--format=%h %s (%cr)"], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> ""
    end
  end

  defp events(path) do
    case File.read(path) do
      {:ok, text} ->
        text
        |> String.split("\n", trim: true)
        |> Enum.take(-15)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.map(&%{time: Map.get(&1, "time", ""), event: Map.get(&1, "event", "")})

      {:error, _} ->
        []
    end
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  @doc """
  A child spec for Bandit on the unix socket at path. An old socket file goes
  first. Erlang makes the socket with the mode 0700, so start_server/1 sets
  0660 after each start with chmod(1): the group luna-api (luna_web) must connect.
  """
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_server, [opts]}, type: :supervisor}

  def start_server(opts) do
    path = Keyword.fetch!(opts, :socket)
    File.rm(path)

    with {:ok, pid} <- Bandit.start_link(plug: {__MODULE__, Keyword.fetch!(opts, :core)}, ip: {:local, path}, port: 0, startup_log: false) do
      # Not File.chmod: Erlang also calls chown(2) there, and the seccomp
      # filter of the unit (~@privileged) kills the process for chown.
      {_, 0} = System.cmd("chmod", ["0660", path])
      {:ok, pid}
    end
  end
end
