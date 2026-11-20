defmodule LunaWeb.WebTest do
  use LunaWeb.Case, async: true

  @owner "owner@example.com"

  defp audit_events do
    %{rows: rows} = LunaWeb.Repo.query!("SELECT event, data FROM audit_events ORDER BY id")
    rows
  end

  test "a request with no login gets 403 and an audit event" do
    conn = get(build_conn(), "/")
    assert conn.status == 403
    assert audit_events() == [["web.refused", %{"reason" => "login", "path" => "/"}]]
  end

  test "a request with a different login gets 403" do
    conn = build_conn() |> put_req_header("tailscale-user-login", "other@example.com") |> get("/")
    assert conn.status == 403
  end

  test "a request with an empty login gets 403" do
    conn = build_conn() |> put_req_header("tailscale-user-login", "") |> get("/")
    assert conn.status == 403
  end

  test "the static files need the login" do
    assert get(build_conn(), "/app.js").status == 403
    conn = build_conn() |> put_req_header("tailscale-user-login", @owner) |> get("/app.js")
    assert conn.status == 200
    # The browser must ask luna each time, so a deploy reaches the page.
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
  end

  test "the owner gets the page with the security headers" do
    conn = build_conn() |> put_req_header("tailscale-user-login", @owner) |> get("/")
    body = html_response(conn, 200)
    assert body =~ "<title>LUNA</title>"
    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "script-src 'self'"
    assert csp =~ "font-src 'self'"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "the mount itself refuses a session with no owner login" do
    socket = %Phoenix.LiveView.Socket{}
    assert {:ok, %{redirected: {:redirect, %{to: "/"}}}} = LunaWeb.HomeLive.mount(%{}, %{}, socket)
  end

  test "the LiveView mount refuses a session with no owner login" do
    socket = %Phoenix.LiveView.Socket{}
    assert {:halt, _} = LunaWeb.Owner.on_mount(:owner, %{}, %{}, socket)
    assert {:halt, _} = LunaWeb.Owner.on_mount(:owner, %{}, %{"owner_login" => "x"}, socket)
    assert {:cont, _} = LunaWeb.Owner.on_mount(:owner, %{}, %{"owner_login" => @owner}, socket)
  end
end
