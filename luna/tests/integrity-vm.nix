# The VM test of modules/luna/integrity.nix (blue team, B3 and B4). Run it with: make integrity-vm-test
{ testers }:

testers.runNixOSTest {
  name = "luna-integrity";
  node.specialArgs.site = { ownerTimeZone = "Australia/Perth"; };
  nodes.machine = { pkgs, ... }: {
    imports = [ ../../modules/luna/integrity.nix ];
    environment.systemPackages = [ pkgs.jq ];
    # A fake core API on the unix socket: it writes the path and the body of each POST to /tmp/posts.
    systemd.services.fake-core = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /run/luna-api
        rm -f /run/luna-api/api.sock
        exec ${pkgs.python3}/bin/python3 ${pkgs.writeText "fake-core.py" ''
          import http.server, json, socketserver
          class Handler(http.server.BaseHTTPRequestHandler):
              def do_POST(self):
                  body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                  with open("/tmp/posts", "a") as f:
                      f.write(self.path + " " + body["text"].replace("\n", " | ") + "\n")
                  self.send_response(200)
                  self.send_header("Content-Length", "2")
                  self.end_headers()
                  self.wfile.write(b"{}")
              def address_string(self):
                  return "unix"
          socketserver.UnixStreamServer("/run/luna-api/api.sock", Handler).serve_forever()
        ''}
      '';
    };
  };
  testScript = ''
    machine.wait_for_unit("fake-core.service")
    machine.wait_for_file("/run/luna-api/api.sock")
    machine.succeed("test -s /var/lib/luna-integrity/baseline")
    machine.succeed("test \"$(cat /var/lib/luna-integrity/expected-system)\" = \"$(readlink -f /run/current-system)\"")

    # A clean system: the check sends no alert.
    machine.succeed("systemctl start luna-integrity.service")
    machine.succeed("jq -e '.changed == \"\" and .system_ok' /var/lib/luna-integrity/last.json")
    machine.fail("grep -q /api/alert /tmp/posts")

    # An attacker adds an SSH key for root: the check names the file.
    machine.succeed("mkdir -p /root/.ssh && echo 'ssh-ed25519 AAAA attacker' >> /root/.ssh/authorized_keys")
    machine.succeed("systemctl start luna-integrity.service")
    machine.wait_until_succeeds("grep -q '/api/alert Integrity: changed since the last deploy: /root/.ssh/authorized_keys' /tmp/posts")

    # The brief: one notice, with the problem in it.
    machine.succeed("systemctl start luna-security-brief.service")
    machine.wait_until_succeeds("grep -q '/api/notice \\*\\*Security brief' /tmp/posts")
    out = machine.succeed("grep /api/notice /tmp/posts")
    assert "Integrity: PROBLEMS" in out, out
    assert "nixpkgs:" in out and "Disk:" in out, out
    print(out)
  '';
}
