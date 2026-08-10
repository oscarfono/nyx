# Nyx — project summary

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
declarative passwords · Bluetooth · Steam · tree-sitter grammars · voice
dictation (whisper.cpp, local) · restic backups to Exoscale · nh/comma
tooling · battery and performance specialisations.

**Suspend measured:** 85% → 79% over 8h26m in S3, about 0.7%/hour. Roughly
six days suspended on a full charge. Clean resume, wifi survived, no wake
events. 85% is the TLP charge ceiling, so that was full by this machine's
definition.

Untested: external displays, dock, fingerprint reader.

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
modules/backup.nix     restic to Exoscale SOS, daily timer
modules/gaming.nix     Steam, gamemode, protontricks
modules/fonts.nix      CommitMono, Raleway, Caveat
home/desktop.nix       hyprland.lua, waybar, mako, fuzzel, hyprlock, ghostty
home/theme.nix         GTK/Qt dark, WhiteSur icons, Bibata cursors
home/menu.nix          renders lib/menu.nix into dispatch scripts
home/wallpaper.nix     swaybg unit + nyx-wallpaper script
home/tools.nix         nyx-shot, nyx-record, nyx-remind
home/emacs.nix         .emacs.d clone + straight seed (user service)
home/treesitter.nix    prebuilt grammars into ~/.emacs.d/tree-sitter
home/dictation.nix     whisper.cpp, SUPER+D toggle
home/xdg.nix           default applications
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
`SUPER+D` dictation · `SUPER+SHIFT+L` lock · `SUPER+1-9` workspaces ·
`Print` region to clipboard ·
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
15. **`hyprctl dispatch` parses its argument as Lua now.**
    `hyprctl dispatch dpms off` fails silently; the form is
    `hyprctl dispatch 'hl.dsp.dpms({ state = "off" })'`. Anything still
    using the old syntax is quietly doing nothing.
16. **Never fix a dpms `off` without its matching `on`.** With both broken
    the screen simply never blanks. Fix only the `off` and you get a black
    screen with no way back — reboot territory. `Ctrl+Alt+F2` still works.
17. **Secrets are 0400 root.** `sudo -E` does not help because sudo drops the
    environment; source the env file *inside* the root shell:
    `sudo sh -c 'set -a; . /run/secrets/x; set +a; cmd'`.
18. **`programs.nh.clean` and `nix.gc.automatic` conflict.** Pick one.
19. **Deleting a file that a .nix still references** gives "Path does not
    exist in Git repository", which reads like a git problem and is not.
20. **`nyx-wallpaper` keeps state in `~/.local/state/nyx/wallpaper`.** A
    stale path there survives a config change, because the old image is
    still in the store until the next GC.

## Backups

restic to Exoscale Simple Object Storage, Geneva (`sos-ch-gva-2`). Swiss
company, Swiss jurisdiction, data never leaves the zone's country. Client-side
encryption means the provider holds opaque blobs regardless.

Daily timer, `Persistent` so it catches up after the machine was off. Every
run after the first is incremental — restic dedupes at block level. Retention
is 7 daily, 5 weekly, 12 monthly, pruned in the same run.

First snapshot: 17,320 files, 515 MiB, 392 MiB stored. Restore verified.

Backed up: `.shh`, `.ssh`, `.gnupg`, `.emacs.d`, Documents, Projects,
Pictures. Excluded: `.git`, `node_modules`, `target`, `result`, `.direnv`,
`straight/build`, `eln-cache`. The Nix store is not backed up; the flake
rebuilds it.

Credentials are two sops secrets: `restic-password` and `restic-s3-env`
(an EnvironmentFile with the Exoscale IAM key, secret and region).

```bash
# run one now
sudo systemctl start restic-backups-beta.service

# anything needing the repo directly must source the env as root
sudo sh -c 'set -a; . /run/secrets/restic-s3-env; set +a; \
  restic -r s3:https://sos-ch-gva-2.exo.io/beta-backup-bucket \
  --password-file /run/secrets/restic-password snapshots'
```

**Losing `restic-password` loses the backups.** Keep a copy off this machine.

## Antivirus

No daemon: it holds the whole signature set in memory (~1GB), and on a
read-only, hash-verified store the realistic threat is passing an infected
file to someone else rather than local infection.

Instead, a weekly `clamscan` of `~/Downloads` and `~/Documents`, niced to 19
with idle IO. It reports and never removes — a false positive deleting my own
file is worse than the malware. `SuccessExitStatus = [ 1 ]` because clamscan
exits 1 when it *finds* something, which systemd would otherwise call a
failure. Results: `journalctl -u clamav-scan`.

freshclam is ordered after `network-online.target` with a retry, because it
was firing the instant the machine resumed and failing on DNS.

## Secrets

Two recipients in `.sops.yaml`: `&beta`, the **host** SSH key
(`ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`), and a personal age key at
`~/.config/sops/age/keys.txt`. The host key lets sops-nix decrypt at
activation; the personal key lets me run `sops secrets/secrets.yaml` as
myself without sudo.

The personal key cannot live inside the backups it protects. Keep it off
this machine.

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

- [x] Versioning and object lock enabled on the Exoscale bucket.
- [x] Age key and restic password in KeePassXC on the MacBook. **That
      database is not itself backed up** — find a better home, or print them.
- [ ] Tighten DNS to `DNSSEC = "true"` / `DNSOverTLS = "true"` once
      opportunistic mode is proven on the networks I use.
- [ ] lanzaboote: enrol keys with `sbctl` **before** enabling, TPM2
      `systemd-cryptenroll` only **after** (PCR 7 binds to Secure Boot state).
- [ ] `thunderbolt` is blacklisted in `security.nix` — remove if using a dock.
- [ ] External displays; dock; fingerprint reader.
- [ ] Second host via `mkHost` — the multi-machine abstraction is untested.
- [ ] Per-language editor setup; wallpaper picker with thumbnails;
      melancholy as a bat `.tmTheme`.
