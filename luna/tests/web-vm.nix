# The VM test of modules/luna/web.nix. Run it with: make web-vm-test
{ testers }:

testers.runNixOSTest {
  name = "luna-web";
  node.specialArgs = {
    hostName = "luna";
    site = { tailnet = "example.ts.net"; ownerLogin = "owner@example.com"; };
  };
  nodes.machine = { pkgs, ... }: {
    imports = [ ../../modules/luna/web.nix ];
    environment.systemPackages = [ pkgs.curl ];
  };
  testScript = ''
    owner = "-H 'Tailscale-User-Login: owner@example.com'"
    machine.wait_for_unit("luna-web.service")
    machine.wait_for_open_port(8091)
    machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8091/ | grep -x 403")
    page = machine.succeed(f"curl -sf {owner} http://127.0.0.1:8091/")
    assert "Approvals" in page, page
    machine.succeed("id -nG luna_web | grep -w luna-api")
    machine.succeed(f"curl -sf {owner} http://127.0.0.1:8091/vendor/phoenix_live_view.min.js >/dev/null")
    machine.fail("ss -ltn | grep -E ':(5432|4369) '")
    events = machine.succeed("sudo -u luna_web psql -tA -c 'SELECT event FROM audit_events' luna_web")
    assert "web.refused" in events, events
    machine.fail("sudo -u luna_web psql -c 'DELETE FROM audit_events' luna_web")
    machine.succeed("systemctl restart luna-web.service")
    machine.wait_for_open_port(8091)
  '';
}
