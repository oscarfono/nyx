# Nyx — project summary

Paste this into a new session to pick up where the last one left off.

## What Nyx is

**Nyx** ("Not Your X") is my standalone, security-first NixOS desktop config
for a Lenovo ThinkPad T490, hostname `beta`, user `coops`. It takes the *idea*
of DHH's Omarchy (opinionated, keyboard-driven Hyprland desktop) and rebuilds
it the way NixOS wants it built: declarative modules, no install scripts, no
runtime mutation.

It is **not** a wrapper around `henrysipp/omarchy-nix` or `T00fy/omanix`.
Both were studied; neither is a dependency.

Repo: `github.com/oscarfono/nyx` (public). Working copy: `~/Projects/nyx`.

## Status: installed and working

LUKS-encrypted root · greetd/regreet · plymouth boot · Hyprland (Lua config)
· Waybar · fuzzel · walker menus · mako · ghostty · zsh · Emacs daemon with
straight.el · swaybg wallpapers · Quad9 DNS over TLS · sops-nix secrets with
declarative passwords · Bluetooth · Steam · tree-sitter grammars.

Untested: battery life over a full day, external displays, dock, fingerprint
reader.

## Decisions, and why

| Decision | Reasoning |
|---|---|
| Flake + config repo, **no ISO** | The installer was 80% of the work for 20% of the value. |
| `nixos-unstable` | Hyprland and desktop tooling move fast. |
| Emacs default editor, straight.el | Nix owns the binary and toolchain; straight owns all elisp. Two package managers on one load-path is the failure mode. |
| Brave default, Firefox alongside | Chromium engine accepted knowingly; de-Googling here is about services, not the engine. Locked down via managed policy JSON. |
| KeePassXC, local kdbx | No cloud password vendor. |
| Hyprland config as **Lua**, hand-generated | hyprlang is deprecated as of 0.55 and goes away in 0.57. home-manager's serialiser emits invalid Lua, so we write it ourselves from Nix data. |
| Every bind wrapped in `pcall` | A Lua error before the binds means NO binds and emergency mode. `pcall` costs one bind instead of the session. |
| swaybg, not hyprpaper | hyprpaper reported "monitor has no target" while its IPC rejected every request. swaybg has no IPC: write path, restart unit. |
| Fuzzel for apps, Walker for menus | Walker `--dmenu` drives the generated menu tree. |
| melancholy everywhere | `lib/melancholy.nix` is the single source of colour truth. |
| opentofu, not terraform | Terraform is BSL 1.1. `terraform=tofu` alias covers muscle memory. |
| Unfree allow-listed per package | One list, in `apps.nix`. It doubles as the inventory. |

## Layout

```
flake.nix              inputs, mkHost, the `beta` output
.sops.yaml             age recipients. &beta is the HOST ssh key.
secrets/secrets.yaml   encrypted. Contains coops-password (yescrypt).
lib/melancholy.nix     the palette (bg #2A2A2A, fg #DEDEDE, amber #FFB728)
lib/menu.nix           menu tree as data
modules/desktop.nix    Hyprland, greetd/regreet, plymouth, pipewire, capture
modules/apps.nix       Brave, Firefox, KeePassXC, Claude Code, unfree list
modules/emacs.nix      Emacs binary + native-comp toolchain (no elisp)
modules/devops.nix     containers, k8s, IaC, network tools, nix settings
modules/security.nix   hardening, DNS, firewall, audit, Secure Boot (opt-in)
modules/secrets.nix    sops-nix, declarative user passwords
modules/power.nix      power, battery, deep sleep
modules/bluetooth.nix  bluez, blueman, A2DP codec preferences
modules/gaming.nix     Steam, gamemode, protontricks
modules/fonts.nix      CommitMono, Raleway, Caveat
home/desktop.nix       hyprland.lua, waybar, mako, fuzzel, hyprlock, ghostty
home/theme.nix         GTK/Qt dark, WhiteSur icons, Bibata cursors
home/menu.nix          renders lib/menu.nix into dispatch scripts
home/wallpaper.nix     swaybg unit + nyx-wallpaper script
home/tools.nix         nyx-shot, nyx-record, nyx-remind
home/emacs.nix         .emacs.d clone + straight seed (user service)
home/treesitter.nix    prebuilt grammars into ~/.emacs.d/tree-sitter
home/agents.nix        agent tooling
hosts/t490/            hardware profile, host settings
```

## Multiple machines

`flake.nix` defines `mkHost`. A new machine is an entry in
`nixosConfigurations`, not a fork. `hostName`, `username`, `hardware`,
`hostPath` and the module list are all arguments.

## Keybindings

`SUPER+Return` terminal · `SUPER+E` Emacs · `SUPER+B` Brave ·
`SUPER+SHIFT+B` Firefox · `SUPER+P` KeePassXC · `SUPER+N` files ·
`SUPER+C` calculator · `SUPER+A` Claude Code · `SUPER+Space` launcher ·
`SUPER+ALT+Space` menu · `SUPER+K` cheatsheet · `SUPER+Q` close ·
`SUPER+F` fullscreen · `SUPER+V` float · `SUPER+CTRL+arrows` resize ·
`SUPER+SHIFT+L` lock · `SUPER+1-9` workspaces · `Print` region to clipboard ·
`SHIFT+Print` to satty · `SUPER+SHIFT+R` record toggle.

Menu sections: Style, Capture, Tools, Network, Nix, System, Session, Learn.

## Hard-won lessons (do not relearn these)

1. **Nothing network-dependent in a home-manager activation script.**
   Activation runs before the network and under `set -e`; a failed `git
   clone` aborted the entire user config. Bootstrapping is a
   `systemd.user.service` after `network-online.target` that swallows its
   own failures.
2. **Set `home-manager.backupFileExtension`.** One stray pre-existing file
   blocked all of activation.
3. **`initialPassword` is a no-op if the account already exists.**
4. **`nixos-rebuild test` does not survive a reboot.** Check
   `readlink -f /run/current-system` against
   `readlink -f /nix/var/nix/profiles/system` — if they differ you are on a
   test generation.
5. **Run `passwd` after install.** Not doing so cost a full reinstall:
   `pam_unix: auth could not identify password` means no hash exists, and no
   generation can fix it because they share `/etc/shadow`.
6. **Flakes read the git index.** Edit without `git add` and Nix evaluates
   the old state.
7. **A running service predates the config that replaced it.** Restart the
   unit before debugging.
8. **`FallbackDNS` is only consulted when no other DNS is configured.**
   Quad9 belongs in `DNS` with `Domains = "~."`. Strict DNSSEC + strict
   DNSOverTLS against a DHCP resolver breaks every lookup.
9. **Nix wants a semicolon after every attribute**, including the last.
10. **In `''` strings, `''` is the escape character.** It cannot appear
    literally, not even inside a comment within the string.
11. **Nested quoting (Nix → Lua → shell) is where configs break.** If a
    command needs quotes or `$(...)`, put it in a script in `home/tools.nix`
    and call the script.
12. **`allowUnfreePredicate` is a function, not a list.** A second definition
    replaces the first rather than merging. Keep one, in `apps.nix`.
13. **home-manager's gtk module writes the same dconf keys you might set by
    hand.** Two different values is a hard conflict.
14. **sops `neededForUsers` secrets land in `/run/secrets-for-users`,**
    not `/run/secrets`.

## Secrets

`.sops.yaml` recipient `&beta` is the **host** SSH key
(`ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`), so only this machine
decrypts. A reinstall generates a new host key and orphans the file — add a
personal age key as a second recipient before that becomes a problem.

`users.mutableUsers = false`; the password comes from
`/run/secrets-for-users/coops-password`. `passwd` is therefore a no-op.
To change it: `mkpasswd -m yescrypt`, `sops secrets/secrets.yaml`, rebuild.

Verify a hash matches a password:
`mkpasswd -S "$(sudo cat /run/secrets-for-users/coops-password)" <password>`

## Daily use

```bash
cd ~/Projects/nyx
$EDITOR modules/whatever.nix
git add -A                      # flakes read the git INDEX
sudo nixos-rebuild test --flake .#beta      # prove it
sudo nixos-rebuild switch --flake .#beta    # keep it
```

Full command reference in `CHEATSHEET.md`.

Never change boot or crypto in the same generation as anything else. Old
generations are in the boot menu; that safety net does not cover LUKS,
lanzaboote or `mutableUsers = false`.

## Next actions

- [ ] Voice dictation (whisper), Omarchy-style.
- [ ] Add a personal age key to `.sops.yaml` as a second recipient.
- [ ] Tighten DNS to `DNSSEC = "true"` / `DNSOverTLS = "true"` once
      opportunistic mode is proven on the networks I use.
- [ ] lanzaboote: enrol keys with `sbctl` **before** enabling, TPM2
      `systemd-cryptenroll` only **after** (PCR 7 binds to Secure Boot state).
- [ ] `thunderbolt` is blacklisted in `security.nix` — remove if using a dock.
- [ ] Battery life over a full day; external displays; dock; fingerprint.
- [ ] Per-language editor setup; wallpaper picker with thumbnails;
      melancholy as a bat `.tmTheme`.
