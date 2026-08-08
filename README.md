# Nyx

**Not Your X.** An opinionated, security-first NixOS desktop.

Nyx is its own distribution config, not a wrapper around anyone else's.
Omarchy proved that an opinionated, keyboard-driven Hyprland desktop is
worth having. Nyx takes that idea and rebuilds it the way NixOS wants it
built: declarative modules, no install scripts, no runtime mutation, and a
security posture that is written down rather than assumed.

Target: Lenovo ThinkPad T490s (hostname `beta`).

## Layout

```
flake.nix              inputs, the `beta` host output
lib/melancholy.nix     the palette. Single source of colour truth.
lib/menu.nix           the menu tree as data, rendered into scripts at build
modules/desktop.nix    Hyprland, greetd, audio, portals, capture tools
modules/apps.nix       Brave, Firefox, KeePassXC, Claude Code
modules/emacs.nix      Emacs + straight.el toolchain
modules/devops.nix     containers, k8s, IaC, secrets, network tooling
modules/security.nix   hardening, DNS, firewall, audit, Secure Boot (opt-in)
modules/power.nix      T490s power, battery, suspend
modules/fonts.nix      CommitMono, Raleway, Caveat
home/                  user layer: desktop theming, menus, shell, git, Emacs
hosts/t490s/           hardware profile and host settings
```

## Prior art

Studied, not depended on:

- [basecamp/omarchy](https://github.com/basecamp/omarchy) - the original
- [T00fy/omanix](https://github.com/T00fy/omanix) - the most complete NixOS
  port. Good reference for capture pipelines and menu design.
- [henrysipp/omarchy-nix](https://github.com/henrysipp/omarchy-nix) - earlier
  port, now unmaintained.

## What makes it Nyx

| | Typical Omarchy port | Nyx |
|---|---|---|
| Editor | Neovim | Emacs (straight.el) + Neovim |
| Browser | Chromium | Brave with managed policy, Firefox alongside |
| Passwords | 1Password | KeePassXC, local kdbx |
| Assistant | ChatGPT wrapper | Claude Code |
| Theme | Tokyo Night | melancholy, everywhere |
| DNS | system default | Quad9 over TLS with DNSSEC |
| Secrets | none | sops-nix |
| Secure Boot | none | lanzaboote, wired but opt-in |
| MAC address | static | randomised per connection |
| sudo | sudo | sudo-rs, wheel-only |
| LSM / audit | none | AppArmor, auditd |
| Laptop power | unhandled | TLP, deep sleep, charge thresholds |

## First build

```bash
sudo nixos-generate-config --show-hardware-config > hosts/t490s/hardware-configuration.nix
git add -A                       # flakes read from the git index
nix flake check
sudo nixos-rebuild build --flake .#beta
sudo nixos-rebuild build-vm --flake .#beta && ./result/bin/run-beta-vm
sudo nixos-rebuild switch --flake .#beta
```

## Post-install, in order

1. Boot, confirm Hyprland, wifi, audio, brightness, suspend.
2. KeePassXC database on the encrypted root.
3. sops secrets, then declarative user password.
4. `sbctl` keys, then lanzaboote.
5. Only after 4: `systemd-cryptenroll` for TPM2 unlock.

Steps 4 and 5 can leave you unbootable. One at a time, live USB in the drawer.
