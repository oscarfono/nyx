defmodule LunaWeb.Voice do
  @moduledoc """
  Voice turns: speech to text, the core, then text to speech, one sentence
  at a time. Refer to "Voice" in LUNA.org.

  A voice turn goes to the chat endpoint only. A voice turn can never
  approve a request (backlog #5).
  """

  alias LunaWeb.{Core, Wyoming}

  # 60 seconds of 16 kHz, 16-bit, mono audio.
  @max_pcm_bytes 16_000 * 2 * 60
  # Less than 0.3 seconds of audio is a slip of the finger.
  @min_pcm_bytes 16_000 * 2 * 3 |> div(10)

  def max_pcm_bytes, do: @max_pcm_bytes

  @doc "Speech to text. Returns {:ok, text} or {:error, message}."
  def transcribe(pcm) when byte_size(pcm) < @min_pcm_bytes, do: {:error, "I did not hear anything."}
  def transcribe(pcm) when byte_size(pcm) > @max_pcm_bytes, do: {:error, "Keep a voice message under one minute."}

  def transcribe(pcm) do
    case Wyoming.transcribe(pcm, server(:stt)) do
      {:ok, ""} -> {:error, "I did not hear anything."}
      other -> other
    end
  end

  @doc "Sends the transcript to the core as a voice message."
  def ask(text), do: Core.chat(text, nil, "voice")

  @doc "Text to speech for one sentence."
  def synthesize(sentence), do: Wyoming.synthesize(sentence, server(:tts))

  @doc """
  Makes the text fit for speech, and cuts it into sentences.
  A long first sentence is cut at its first comma, so the first audio comes sooner.
  """
  def sentences(text) do
    text
    |> String.replace(~r/```.*?```/s, " ")
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "|"))
    |> Enum.map(&String.replace(&1, ~r/^\s*(#+|[-*+]|\d+\.)\s+/, ""))
    |> Enum.join(" ")
    |> String.replace(~r/[*_`#>]/, "")
    |> String.replace(~r/\[([^\]]+)\]\([^)]+\)/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split(~r/(?<=[.!?])\s+/, trim: true)
    |> split_first()
  end

  defp split_first([first | rest]) when byte_size(first) > 80 do
    case String.split(first, ~r/(?<=,)\s+/, parts: 2) do
      [a, b] -> [a, b | rest]
      _ -> [first | rest]
    end
  end

  defp split_first(list), do: list

  defp server(key) do
    uri = Application.fetch_env!(:luna_web, :voice) |> Keyword.fetch!(key) |> URI.parse()
    {uri.host, uri.port}
  end
end
