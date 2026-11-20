# The VM test of modules/luna/egress.nix (blue team, B1). Run it with: make egress-vm-test
{ testers }:

testers.runNixOSTest {
  name = "luna-egress";
  node.specialArgs.site = { telegram = false; wise = { mode = "off"; sandbox = true; }; };
  nodes.machine = { pkgs, ... }: {
    imports = [ ../../modules/luna/egress.nix ];
    environment.systemPackages = [ pkgs.curl ];
    # Stand-ins for the units that egress.nix restricts.
    systemd.services.luna-core.script = "sleep infinity";
    systemd.services.luna-web.script = "sleep infinity";
  };
  testScript = ''
    machine.wait_for_unit("tinyproxy.service")
    machine.wait_for_open_port(8888)

    # A host that is not in the allowlist: the proxy refuses it.
    out = machine.succeed("curl -s -o /dev/null -w '%{http_connect}' -x http://127.0.0.1:8888 https://example.com || true")
    assert "403" in out, f"example.com was not refused: {out}"

    # A host in the allowlist passes the filter. The VM has no internet, so the
    # proxy fails after the filter, with a code that is not 403.
    out = machine.succeed("curl -s -o /dev/null -w '%{http_connect}' -x http://127.0.0.1:8888 https://api.anthropic.com || true")
    assert "403" not in out, f"api.anthropic.com was refused by the filter: {out}"

    # A port other than 443 is refused for CONNECT.
    out = machine.succeed("curl -s -o /dev/null -w '%{http_connect}' -x http://127.0.0.1:8888 https://api.anthropic.com:8443 || true")
    assert "403" in out, f"port 8443 was not refused: {out}"

    # The sandbox of the core: the kernel refuses a direct connection.
    # (For HTTPS through a proxy, curl gives the answer of the proxy in http_connect.)
    out = machine.fail("systemd-run --wait --pipe -p IPAddressDeny=any -p IPAddressAllow=localhost curl -sS --max-time 5 http://10.0.2.2/ 2>&1")
    # Through the proxy, from the same sandbox, the filter answers.
    out = machine.succeed("systemd-run --wait --pipe -p IPAddressDeny=any -p IPAddressAllow=localhost curl -s -o /dev/null -w '%{http_connect}' -x http://127.0.0.1:8888 https://example.com || true")
    assert "403" in out, out

    # The refusal is in the journal, for the alerts of B2.
    machine.succeed("journalctl -u tinyproxy --no-pager | grep -i 'filtered'")
  '';
}
