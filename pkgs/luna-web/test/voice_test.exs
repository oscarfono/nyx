defmodule LunaWeb.VoiceTest do
  # One fake core and one fake voice server serve all tests.
  use LunaWeb.Case, async: false

  alias LunaWeb.{FakeCore, FakeWyoming, Voice, Wyoming}

  setup do
    FakeCore.reset()
    FakeWyoming.reset()
  end

  # One second of silence: 16 kHz, 16-bit, mono.
  @second :binary.copy(<<0, 0>>, 16_000)

  test "an event has a JSON line, the data, then the payload" do
    [line, "\n", data, payload] = Wyoming.encode("audio-chunk", %{"rate" => 16_000}, "abc")
    header = Jason.decode!(line)
    assert header["type"] == "audio-chunk"
    assert header["data_length"] == byte_size(data)
    assert header["payload_length"] == 3
    assert payload == "abc"
  end

  test "speech to text sends all the audio and returns the transcript" do
    assert Voice.transcribe(@second) == {:ok, "hello luna"}
    state = FakeWyoming.state()
    assert hd(state.events) == "transcribe"
    assert List.last(state.events) == "audio-stop"
    assert state.bytes == byte_size(@second)
  end

  test "a very short or a very long recording does not go to the server" do
    assert {:error, _} = Voice.transcribe(binary_part(@second, 0, 100))
    assert {:error, _} = Voice.transcribe(:binary.copy(@second, 61))
    assert FakeWyoming.state().events == []
  end

  test "an empty transcript is an error" do
    FakeWyoming.reset("  ")
    assert {:error, "I did not hear anything."} = Voice.transcribe(@second)
  end

  test "text to speech returns the PCM and its rate" do
    assert {:ok, %{rate: 22_050, pcm: "Hi."}} = Voice.synthesize("Hi.")
  end

  test "a voice turn goes to chat as a voice message" do
    assert Voice.ask("next swing?") == {:ok, "reply: next swing?"}
    assert [{"POST", "/api/chat", %{"text" => "next swing?", "channel" => "voice"}}] = FakeCore.requests()
  end

  test "a voice turn cannot approve a request" do
    FakeWyoming.reset("approve a1b2c3")
    {:ok, text} = Voice.transcribe(@second)
    assert {:ok, _} = Voice.ask(text)
    assert [{"POST", "/api/chat", %{"channel" => "voice"}}] = FakeCore.requests()
  end

  test "a text message has the channel text" do
    assert {:ok, _} = LunaWeb.Core.chat("hi", nil)
    assert [{"POST", "/api/chat", %{"channel" => "text"}}] = FakeCore.requests()
  end

  test "the text for speech has no Markdown, and comes in sentences" do
    text = """
    ## Plan
    **Safe to spend:** $120. See [the plan](https://example.com).
    - Rent is due Friday!
    | a | b |
    Next swing starts in 9 days?
    """

    assert Voice.sentences(text) == [
             "Plan Safe to spend: $120.",
             "See the plan.",
             "Rent is due Friday!",
             "Next swing starts in 9 days?"
           ]
  end

  test "a long first sentence is cut at its first comma" do
    long = "Your safe-to-spend number this week is lower than last week, because the car insurance is due."
    assert [first, second] = Voice.sentences(long)
    assert String.ends_with?(first, ",")
    assert String.starts_with?(second, "because")
  end
end
