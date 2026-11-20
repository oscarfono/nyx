defmodule LunaCore.HttpTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Claude, FakeClaude, Http}

  test "no proxy without LUNA_HTTPS_PROXY" do
    assert Http.options(%{}) == []
  end

  test "the proxy from LUNA_HTTPS_PROXY" do
    assert Http.options(%{"LUNA_HTTPS_PROXY" => "http://127.0.0.1:8888"}) ==
             [connect_options: [proxy: {:http, "127.0.0.1", 8888, []}]]
  end

  test "a Claude call goes through the proxy, not to the host" do
    # The fake is the proxy here. The target host does not exist, so only the
    # proxy can answer.
    fake = FakeClaude.start([{200, FakeClaude.message("end_turn", [FakeClaude.text("via the proxy")])}])
    %URI{port: port} = URI.parse(fake.base_url)

    assert {:ok, %{"content" => [%{"text" => "via the proxy"}]}} =
             Claude.create(%{"model" => "m"},
               api_key: "k", base_url: "http://api.luna-test.invalid", max_retries: 0,
               http: [connect_options: [proxy: {:http, "127.0.0.1", port, []}]])

    assert [%{body: %{"model" => "m"}}] = FakeClaude.requests(fake)
  end
end
