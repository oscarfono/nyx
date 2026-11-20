defmodule LunaWeb.Wyoming do
  @moduledoc """
  A client of the Wyoming protocol, for speech to text and text to speech.

  An event is one JSON line, then the optional data bytes, then the optional
  payload bytes. The line gives the lengths in data_length and payload_length.
  Refer to "Voice" in LUNA.org.
  """

  @version "1.11.0"
  @rate 16_000
  @chunk_bytes 6_400
  @timeout :timer.seconds(30)

  @doc "Sends 16 kHz, 16-bit, mono PCM to the STT server. Returns the text."
  def transcribe(pcm, {host, port}) when is_binary(pcm) do
    format = %{"rate" => @rate, "width" => 2, "channels" => 1}

    with {:ok, socket} <- connect(host, port) do
      try do
        :ok = send_event(socket, "transcribe", %{"language" => "en"})
        :ok = send_event(socket, "audio-start", format)

        for <<chunk::binary-size(@chunk_bytes) <- pcm>> do
          :ok = send_event(socket, "audio-chunk", format, chunk)
        end

        rest = binary_part(pcm, div(byte_size(pcm), @chunk_bytes) * @chunk_bytes, rem(byte_size(pcm), @chunk_bytes))
        if rest != "", do: :ok = send_event(socket, "audio-chunk", format, rest)
        :ok = send_event(socket, "audio-stop", %{})

        case read_until(socket, ["transcript"]) do
          {:ok, {"transcript", %{"text" => text}, _}} -> {:ok, String.trim(text)}
          {:error, reason} -> {:error, reason}
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  @doc "Sends text to the TTS server. Returns the PCM and its format."
  def synthesize(text, {host, port}) when is_binary(text) do
    with {:ok, socket} <- connect(host, port) do
      try do
        :ok = send_event(socket, "synthesize", %{"text" => text})
        collect(socket, nil, [])
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp collect(socket, format, chunks) do
    case read_event(socket) do
      {:ok, {"audio-start", data, _}} ->
        collect(socket, data, chunks)

      {:ok, {"audio-chunk", data, payload}} ->
        collect(socket, format || data, [chunks, payload || ""])

      {:ok, {"audio-stop", _, _}} when format != nil ->
        {:ok, %{rate: format["rate"], width: format["width"], channels: format["channels"],
                pcm: IO.iodata_to_binary(chunks)}}

      {:ok, {"error", data, _}} ->
        {:error, Map.get(data, "text", "The voice server sent an error.")}

      {:ok, _other} ->
        collect(socket, format, chunks)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_until(socket, types) do
    case read_event(socket) do
      {:ok, {type, _, _} = event} -> if type in types, do: {:ok, event}, else: read_until(socket, types)
      error -> error
    end
  end

  defp connect(host, port) do
    case :gen_tcp.connect(to_charlist(host), port, [:binary, active: false, packet: :line], @timeout) do
      {:ok, socket} -> {:ok, socket}
      {:error, _} -> {:error, "The voice server is not available."}
    end
  end

  @doc false
  def encode(type, data, payload \\ nil) do
    data_bytes = if data == %{}, do: "", else: Jason.encode!(data)

    header =
      %{"type" => type, "version" => @version}
      |> put_length("data_length", data_bytes)
      |> put_length("payload_length", payload || "")

    [Jason.encode!(header), "\n", data_bytes, payload || ""]
  end

  defp put_length(header, _key, ""), do: header
  defp put_length(header, key, bytes), do: Map.put(header, key, byte_size(bytes))

  defp send_event(socket, type, data, payload \\ nil) do
    case :gen_tcp.send(socket, encode(type, data, payload)) do
      :ok -> :ok
      {:error, _} -> {:error, "The voice server closed the connection."}
    end
  end

  defp read_event(socket) do
    :ok = :inet.setopts(socket, packet: :line)

    with {:ok, line} <- :gen_tcp.recv(socket, 0, @timeout),
         {:ok, header} <- Jason.decode(line),
         :ok <- :inet.setopts(socket, packet: :raw),
         {:ok, data_bytes} <- recv_exact(socket, header["data_length"]),
         {:ok, payload} <- recv_exact(socket, header["payload_length"]) do
      data = Map.merge(header["data"] || %{}, if(data_bytes == "", do: %{}, else: Jason.decode!(data_bytes)))
      {:ok, {header["type"], data, if(payload == "", do: nil, else: payload)}}
    else
      {:error, :timeout} -> {:error, "The voice server did not reply in time."}
      {:error, _} -> {:error, "The voice server sent a bad reply."}
    end
  end

  defp recv_exact(_socket, nil), do: {:ok, ""}
  defp recv_exact(_socket, 0), do: {:ok, ""}
  defp recv_exact(socket, n), do: :gen_tcp.recv(socket, n, @timeout)
end
