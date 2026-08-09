# Nyx — project summary

Paste this into a new session to pick up where the last one left off.

## What Nyx is

**Nyx** ("Not Your X") is my standalone, security-first NixOS desktop config
for a Lenovo ThinkPad T490s, hostname `beta`. It takes the *idea* of DHH's
Omarchy (opinionated, keyboard-driven Hyprland desktop) and rebuilds it the
way NixOS wants it built: declarative modules, no install scripts, no runtime
mutation.

It is **not** a wrapper around `henrysipp/omarchy-nix` or `T00fy/omanix`.
Both were studied; neither is a dependency. I decided that deliberately after
an early version drifted into being a thin config over omanix.

Repo: `github.com/oscarfono/nyx` (public). Working copy: `~/Projects/nyx`.

## Decisions, and why

| Decision | Reasoning |
|---|---|
| Flake + config repo, **no ISO** | The installer was 80% of the work for 20% of the value. Standard NixOS install then `nixos-rebuild --flake` is less work and more idiomatic. |
| `nixos-unstable` | Hyprland and desktop tooling move fast; stable lagged. |
| Emacs default editor, straight.el | My own `.emacs.d` and `melancholy-theme`. Nix owns the binary and toolchain; straight owns all elisp. Two package managers on one load-path is the failure mode I'm avoiding. |
| Brave default, Firefox alongside | Brave is Chromium-engine, which I accept knowingly. De-Googling here is about services and the branded browser, not the engine. Brave locked down via managed policy JSON. |
| KeePassXC, local kdbx | No cloud password vendor. |
| zsh | My preference over fish. |
| Hyprland config written as `hyprland.conf`, **not** via home-manager's module | HM now serialises to `hyprland.lua`; `$mod`, `exec-once` and `col.active_border` are not valid Lua identifiers. Three successive syntax errors showed the abstraction was fighting us. We generate the `.conf` from the same Nix data instead. **This is the single most important gotcha in the repo.** |
| Fuzzel for app launching, Walker for menus | Walker in `--dmenu` mode drives the generated menu tree. |
| melancholy theme everywhere | `lib/melancholy.nix` is the single source of colour truth; every drawing module imports it. |
| opentofu, not terraform | Terraform is BSL 1.1 (unfree). `tofu` is a drop-in; a `terraform=tofu` alias covers muscle memory. |
| Unfree allow-listed per package | Only `brave` and `claude-code`. The list doubles as an inventory. |

## Multiple machines

`flake.nix` defines `mkHost`, so a new machine is an entry in
`nixosConfigurations`, not a fork. Everything machine-specific is an
argument: `hostName`, `username`, `hardware` (a nixos-hardware module or
`null`), `hostPath`, and which of our modules it wants. A headless box drops
`desktop.nix` and `fonts.nix` and keeps `security.nix` and `devops.nix`.
The username is threaded through to home-manager, so the repo is not welded
to one account name — `beta` uses `coops`; another host can use `sod`.

## Layout

```
flake.nix              inputs, the `beta` host output
lib/melancholy.nix     the palette (bg #2A2A2A, fg #DEDEDE, accent amber #FFB728)
lib/menu.nix           menu tree as data
assets/wallpapers/     two melancholy wallpapers
modules/desktop.nix    Hyprland, greetd/tuigreet, pipewire, portals, capture tools
modules/apps.nix       Brave (+managed policy), Firefox, KeePassXC, Claude Code
modules/emacs.nix      Emacs binary + native-comp toolchain (no elisp)
modules/devops.nix     containers, k8s, IaC, secrets, network tools, nix settings
modules/security.nix   hardening, DNS, firewall, audit, Secure Boot (opt-in)
modules/power.nix      T490s power, battery, suspend
modules/fonts.nix      CommitMono, Raleway, Caveat
home/default.nix       identity, zsh, git, neovim, tmpfiles
home/desktop.nix       hyprland.conf, waybar, mako, fuzzel, hyprlock, hypridle, ghostty
home/menu.nix          renders lib/menu.nix into dispatch scripts
home/wallpaper.nix     hyprpaper + generated `nyx-wallpaper` script
home/emacs.nix         .emacs.d + straight.el bootstrap (user service)
hosts/t490s/           hardware profile, host settings, VM variant
```

## Keybindings

`SUPER+Return` terminal · `SUPER+E` Emacs · `SUPER+B` Brave ·
`SUPER+SHIFT+B` Firefox · `SUPER+P` KeePassXC · `SUPER+Space` launcher ·
`SUPER+ALT+Space` menu · `SUPER+K` cheatsheet · `SUPER+Q` close ·
`SUPER+F` fullscreen · `SUPER+V` float · `SUPER+SHIFT+L` lock ·
`SUPER+1-9` workspaces · `Print` region to clipboard · `SHIFT+Print` to satty ·
`SUPER+SHIFT+R` record region.

Menu sections: Style, Capture, Network, Nix, System, Session, Learn.

## Hard-won lessons (do not relearn these)

1. **Never put anything network-dependent in a home-manager activation
   script.** Activation runs before the network is up and under `set -e`; a
   failed `git clone` aborted the *entire* user config — no Hyprland, no
   shell. Bootstrapping now lives in a `systemd.user.service` ordered after
   `network-online.target` that swallows its own failures.
2. **Set `home-manager.backupFileExtension`.** One stray pre-existing file
   (a default `hyprland.lua`) blocked all of activation.
3. **`initialPassword` is a no-op if the account already exists.** Use
   `password` for throwaway VM credentials.
4. **Do not pass `-display gtk,gl=on` / `virtio-vga-gl` to the VM.** QEMU
   aborts on Wayland hosts rather than falling back.
5. **`nix flake check` is weaker than building the VM.** The VM variant
   re-evaluates everything and caught an `EDITOR` conflict that check missed.
6. **Flakes read from the git index.** Edit without `git add` and Nix keeps
   evaluating the old state.
7. Order the Emacs daemon after the bootstrap service, or it starts with no
   config on a fresh machine.
8. **`FallbackDNS` is only consulted when no other DNS is configured.**
   Putting Quad9 there while `DNSSEC`/`DNSOverTLS` were both strict meant
   resolved insisted on DNS-over-TLS to the router's DHCP resolver and every
   lookup failed. Quad9 belongs in `DNS` with `Domains = "~."`.
9. **A running service predates the config that just replaced it.** hyprpaper
   and resolved both looked broken when they were simply still running with
   the previous generation's settings. `systemctl --user restart <unit>`, or
   reboot, before debugging.
10. Nix wants a semicolon after *every* attribute, including the last one in
    a set. `syntax error, unexpected '}', expecting ';'` means look at the
    line above.

## Errors found and fixed along the way

`virtualisation.libvirtd.qemu.ovmf` removed · `pkgs.greetd.tuigreet` → top-level
`pkgs.tuigreet` · `noto-fonts-emoji` → `noto-fonts-color-emoji` · `dogdns`
removed → `doggo` · `rkhunter` not packaged → `vulnix` (better fit: the store is
read-only and hash-verified) · no `aspellDicts.en_AU` (the `en` dict carries
en_AU) · terraform BSL · `programs.git.userName/userEmail/extraConfig` →
`programs.git.settings` · `services.logind.*` → `settings.Login.*` ·
`services.resolved.*` → `settings.Resolve.*` · EDITOR defined twice ·
hardcoded `/home/coops` path · POSIX `||`/`&&` precedence bug in the wallpaper
cycler · DNS unusable from strict DNSSEC + strict DNSOverTLS against a
DHCP-supplied resolver.

## Current state

**Installed and running on the T490s.** Hostname `beta`, user `sod`, built
with `sudo nixos-rebuild switch --flake ~/Projects/nyx#beta`. The repo's
`beta` entry uses `username = "sod"`; anyone else cloning it would change
that one argument.

Working: LUKS-encrypted root, greetd/tuigreet, Hyprland session, Waybar,
fuzzel, mako, ghostty, zsh, Emacs with straight.el (`.emacs.d` cloned,
straight seeded at the pinned commit), hyprpaper with the melancholy
wallpapers, Quad9 DNS.

Untested: suspend/resume, battery life over a real day, external displays,
fingerprint reader, dock behaviour.

## Known gaps / next actions

- [x] Username is a `mkHost` argument. `beta` uses `sod` on my machine.
- [x] straight.el pinned to `adb0fb37bc5fc298f5ed9f61447cfe379fff77ed`, so
      early-init.el's `url-retrieve` of `install.el` never runs.
- [x] `hardware-configuration.nix` regenerated on the real machine.
- [ ] `users.mutableUsers = true` and sops is commented out. Staged: install,
      `passwd`, then sops, then flip to `false`.
- [ ] lanzaboote wired but disabled. Enrol keys with `sbctl` **before**
      enabling, and TPM2 `systemd-cryptenroll` only **after** that (PCR 7
      binds to Secure Boot state).
- [ ] `thunderbolt` is blacklisted in `security.nix` — remove if using a dock.
- [x] Deep sleep: `/sys/power/mem_sleep` reports `s2idle [deep]`, so S3 is
      available and already default. The T490s BIOS has no Sleep State toggle
      and does not need one.
- [ ] Power, battery and suspend still untested in anger. Close the lid,
      leave it overnight, check the drain.
- [ ] Tighten DNS: `DNSSEC = "true"` and `DNSOverTLS = "true"` once I have
      confirmed opportunistic mode works on the networks I actually use.
- [ ] External displays, dock, fingerprint reader.
- [ ] Not yet built: per-language editor setup, wallpaper picker with
      thumbnails, melancholy as a bat `.tmTheme`.

## Daily use

```bash
cd ~/Projects/nyx
$EDITOR modules/whatever.nix
git add -A                      # flakes read the git INDEX, not the worktree
sudo nixos-rebuild switch --flake .#beta
```

Rollback is `sudo nixos-rebuild switch --rollback`, or pick an older
generation from the boot menu. Both are also in the `SUPER+ALT+Space` menu
under Nix, alongside package search, `nix shell`, flake update, GC and a
vulnix CVE scan.

## Install sequence (for the next machine)

The T490s is a SATA M.2, so `/dev/sda` with partitions `sda1`/`sda2` — no
`p` separator. Check with `lsblk` rather than assuming.

1. Boot NixOS ISO. Partition (1G ESP + LUKS container), `mkfs`, mount.
2. `nixos-generate-config --root /mnt`, minimal `configuration.nix`
   (systemd-boot, NetworkManager, a wheel user, git), `nixos-install`, reboot.
3. `git clone https://github.com/oscarfono/nyx.git ~/Projects/nyx`
4. `sudo cp /etc/nixos/hardware-configuration.nix hosts/<host>/`
5. Add a `mkHost` entry in `flake.nix` for the new machine.
6. `git add -A && nix flake check`
7. `sudo nixos-rebuild build --flake .#<host>` then `switch`.
8. `passwd`, reboot, then check: `resolvectl query github.com`,
   `systemctl --user status nyx-emacs-bootstrap hyprpaper`.

Never change boot or crypto in the same generation as anything else. Old
generations are in the boot menu; that safety net does not cover LUKS,
lanzaboote or `mutableUsers = false`.
