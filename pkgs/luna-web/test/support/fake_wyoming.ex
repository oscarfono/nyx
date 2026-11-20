defmodule LunaWeb.FakeWyoming do
  @moduledoc """
  A fake Wyoming server for STT and TTS. It keeps the type of each event that
  it gets, and the count of audio bytes.
  STT replies with the transcript in :transcript. TTS replies with the text as the PCM.
  """

  def start do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :line, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)
    {:ok, _} = Agent.start_link(fn -> %{events: [], bytes: 0, transcript: "hello luna"} end, name: __MODULE__)
    spawn_link(fn -> accept(listen) end)
    uri = "tcp://127.0.0.1:#{port}"
    Application.put_env(:luna_web, :voice, stt: uri, tts: uri)
    :ok
  end

  def reset(transcript \\ "hello luna"),
    do: Agent.update(__MODULE__, fn _ -> %{events: [], bytes: 0, transcript: transcript} end)

  def state, do: Agent.get(__MODULE__, & &1)

  defp accept(listen) do
    {:ok, socket} = :gen_tcp.accept(listen)
    spawn(fn -> serve(socket) end)
    accept(listen)
  end

  defp serve(socket) do
    case read(socket) do
      {:ok, type, data, payload} ->
        Agent.update(__MODULE__, fn s ->
          %{s | events: s.events ++ [type], bytes: s.bytes + byte_size(payload)}
        end)

        reply(socket, type, data)
        serve(socket)

      :closed ->
        :ok
    end
  end

  defp reply(socket, "audio-stop", _) do
    send_event(socket, "transcript", %{"text" => state().transcript})
  end

  defp reply(socket, "synthesize", %{"text" => text}) do
    format = %{"rate" => 22_050, "width" => 2, "channels" => 1}
    send_event(socket, "audio-start", format)
    send_event(socket, "audio-chunk", format, text)
    send_event(socket, "audio-stop", %{})
  end

  defp reply(_socket, _type, _data), do: :ok

  defp send_event(socket, type, data, payload \\ nil),
    do: :gen_tcp.send(socket, LunaWeb.Wyoming.encode(type, data, payload))

  defp read(socket) do
    :inet.setopts(socket, packet: :line)

    with {:ok, line} <- :gen_tcp.recv(socket, 0),
         header = Jason.decode!(line),
         :ok <- :inet.setopts(socket, packet: :raw),
         {:ok, data} <- exact(socket, header["data_length"]),
         {:ok, payload} <- exact(socket, header["payload_length"]) do
      {:ok, header["type"], if(data == "", do: %{}, else: Jason.decode!(data)), payload}
    else
      _ -> :closed
    end
  end

  defp exact(_socket, n) when n in [nil, 0], do: {:ok, ""}
  defp exact(socket, n), do: :gen_tcp.recv(socket, n)
end
