# The VM test of modules/luna/sentry.nix (blue team, B2). Run it with: make sentry-vm-test
{ testers }:

testers.runNixOSTest {
  name = "luna-sentry";
  nodes.machine = { pkgs, ... }: {
    imports = [ ../../modules/luna/sentry.nix ];
    users.groups.luna-api = { };
    # A fake core API on the unix socket: it writes the body of each POST to /tmp/alerts.
    systemd.services.fake-core = {
      wantedBy = [ "multi-user.target" ];
      before = [ "luna-sentry.service" ];
      script = ''
        mkdir -p /run/luna-api
        rm -f /run/luna-api/api.sock
        exec ${pkgs.python3}/bin/python3 ${pkgs.writeText "fake-core.py" ''
          import http.server, os, socketserver
          class Handler(http.server.BaseHTTPRequestHandler):
              def do_POST(self):
                  body = self.rfile.read(int(self.headers["Content-Length"]))
                  with open("/tmp/alerts", "ab") as f:
                      f.write(body + b"\n")
                  self.send_response(200)
                  self.send_header("Content-Length", "2")
                  self.end_headers()
                  self.wfile.write(b"{}")
              def address_string(self):
                  return "unix"
          class Server(socketserver.UnixStreamServer):
              pass
          server = Server("/run/luna-api/api.sock", Handler)
          os.chmod("/run/luna-api/api.sock", 0o666)
          server.serve_forever()
        ''}
      '';
    };
    systemd.services.luna-sentry.after = [ "fake-core.service" ];
    environment.systemPackages = [ pkgs.util-linux ];
  };
  testScript = ''
    machine.wait_for_unit("fake-core.service")
    machine.wait_for_unit("luna-sentry.service")
    machine.sleep(2)

    machine.succeed("logger -t tailscaled 'audit: SSH login: user=root uid=0 from=100.88.0.9 ts_user=coops@example.com node=phone.example.ts.net.'")
    machine.succeed("logger -t tinyproxy 'Proxying refused on filtered domain \"evil.example\"'")
    machine.succeed("systemd-run --unit=boom --wait false || true")

    machine.wait_until_succeeds("grep -q 'SSH login on luna: root, from phone' /tmp/alerts", timeout=30)
    machine.wait_until_succeeds("grep -q 'Egress refused' /tmp/alerts", timeout=30)
    machine.wait_until_succeeds("grep -q 'boom.service failed' /tmp/alerts", timeout=30)

    # A second SSH login in the window gives no second alert.
    machine.succeed("logger -t tailscaled 'audit: SSH login: user=root uid=0 from=100.88.0.9 ts_user=coops@example.com node=phone.example.ts.net.'")
    machine.sleep(3)
    count = machine.succeed("grep -c 'SSH login on luna' /tmp/alerts").strip()
    assert count == "1", f"two SSH alerts in one window: {count}"
  '';
}
