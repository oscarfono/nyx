defmodule LunaCore.Matrix.HtmlTest do
  use ExUnit.Case, async: true

  import LunaCore.Matrix.Html, only: [render: 1]

  test "bold, code, emphasis and line breaks" do
    assert render("**Safe:** `420`\nThat is *fine*.") ==
             "<strong>Safe:</strong> <code>420</code><br>That is <em>fine</em>."
  end

  test "a list" do
    assert render("Bills:\n- rent\n- phone") == "Bills:<br><ul><li>rent</li><li>phone</li></ul>"
  end

  test "a code fence keeps its text, escaped" do
    assert render("```sh\nrm -rf <x>\n```") == "<pre><code>rm -rf &lt;x&gt;\n</code></pre>"
  end

  test "HTML from a web page stays text" do
    html = render(~s|<img src=x onerror="alert(1)"> and <script>alert(2)</script>|)
    refute html =~ "<img"
    refute html =~ "<script"
    assert html =~ "&lt;img src=x onerror=&quot;alert(1)&quot;&gt;"
  end

  test "no tag has an attribute" do
    html = render(~s|**[a](javascript:alert(1))** `x" onclick="y`|)
    refute Regex.match?(~r/<[a-z0-9]+\s/, html)
  end
end
