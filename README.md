# Nyx

**Not Your X.** An opinionated, security-first NixOS desktop for a Lenovo
ThinkPad T490.

Omarchy proved that an opinionated, keyboard-driven Hyprland desktop is
worth having. Nyx takes that idea and builds it the way NixOS wants it
built: declarative modules, no install scripts, no runtime mutation, and a
security posture that is written down rather than assumed.

## Documentation

| File | What it is for |
|---|---|
| `README.md` | this: what Nyx is, and where everything lives |
| `SUMMARY.md` | current state, decisions and why, lessons learnt. Paste into a new session to pick the project back up. |
| `CHEATSHEET.md` | how to do things: rebuild, install, roll back, add a host |
| `KNOWN-ISSUES.md` | every workaround, why it exists, when to retest it |

## What makes it Nyx

| | Typical Omarchy port | Nyx |
|---|---|---|
| Editor | Neovim | Emacs (straight.el) + Neovim |
| Browser | Chromium | Brave with managed policy, Firefox alongside |
| Passwords | 1Password | KeePassXC, local kdbx |
| Assistant | ChatGPT wrapper | Claude Code |
| Theme | Tokyo Night | melancholy, everywhere including terminal output |
| DNS | system default | Quad9 over TLS |
| Secrets | none | sops-nix, declarative user passwords |
| Secure Boot | none | lanzaboote, enforcing, own keys |
| Backups | none | restic to Exoscale, daily, verified |
| MAC address | static | randomised per connection |
| sudo | sudo | sudo-rs, wheel-only |
| LSM / audit | none | AppArmor, auditd |
| Laptop power | unhandled | TLP, deep sleep, charge thresholds |
| Health check | none | `nyx-doctor` |

## Layout

```
flake.nix              inputs, mkHost, the `beta` output
.sops.yaml             age recipients: the host key and my personal key
secrets/secrets.yaml   encrypted: user password, restic credentials

lib/melancholy.nix     the palette. Single source of colour truth.
lib/menu.nix           menu tree as data, rendered into scripts at build
lib/webapps.nix        web apps as data, rendered into desktop entries
assets/                wallpapers and the melancholy bat theme

modules/desktop.nix    Hyprland, greetd/regreet, plymouth, audio, portals
modules/apps.nix       Brave, Firefox, KeePassXC, Claude Code, unfree list
modules/emacs.nix      Emacs binary and the toolchain straight.el needs
modules/languages.nix  LSP servers, formatters, linters
modules/devops.nix     containers, k8s, IaC, nix settings, nh
modules/secops.nix     network, OSINT, forensics, metasploit + postgres
modules/security.nix   hardening, DNS, firewall, audit, Secure Boot
modules/secrets.nix    sops-nix, declarative user passwords
modules/backup.nix     restic to Exoscale, daily timer, nyx-backup
modules/power.nix      power, battery, deep sleep
modules/bluetooth.nix  bluez, blueman applet, A2DP codecs
modules/gaming.nix     Steam, gamemode, protontricks
modules/fonts.nix      CommitMono, JetBrains Mono, Hack, Raleway, Inter, Caveat

home/desktop.nix       hyprland.lua, waybar, fuzzel, hyprlock, ghostty
home/colours.nix       LS_COLORS, zsh highlighting, less, ripgrep, fzf
home/theme.nix         GTK/Qt dark, WhiteSur icons, Bibata cursors
home/tools.nix         nyx-shot, nyx-record, nyx-remind, nyx-doctor, nyx-ws
home/menu.nix          renders lib/menu.nix into dispatch scripts
home/wallpaper.nix     swaybg unit and nyx-wallpaper
home/emacs.nix         .emacs.d clone and straight.el seed
home/dictation.nix     whisper.cpp, SUPER+D
home/report.nix        nyx-report, for filing upstream issues
home/local.nix         escape hatch for personal, unpublished shell functions
hosts/t490/            hardware profile and host settings
```

## Prior art

Studied, not depended on:

- [basecamp/omarchy](https://github.com/basecamp/omarchy) — the original
- [T00fy/omanix](https://github.com/T00fy/omanix) — the most complete NixOS
  port. Good reference for capture pipelines and menu design.
- [henrysipp/omarchy-nix](https://github.com/henrysipp/omarchy-nix) — earlier
  port, now unmaintained.

## Installing on a new machine

See **CHEATSHEET.md**, "Adding a host". The short version: install stock
NixOS, clone this repo, generate `hardware-configuration.nix`, add a
`mkHost` entry, rebuild.

Secure Boot, LUKS and `mutableUsers = false` each go in their own
generation, one at a time, with a live USB to hand. SUMMARY.md explains why.
