{ config, pkgs, lib, username, ... }:

# Metasploit's database connection. Points at the local postgres declared in
# modules/secops.nix, over the unix socket, so there is no password to store
# and nothing listening on the network.
#
# msfconsole reads this automatically. Confirm inside msfconsole with:
#   db_status     ->  Connected to msf. Connection type: postgresql.

{
  home.file.".msf4/database.yml".text = ''
    production:
      adapter: postgresql
      database: msf
      username: ${username}
      host: /run/postgresql
      port: 5432
      pool: 5
      timeout: 5
  '';
}
