# Nyx

An opinionated, security-first NixOS desktop. Omarchy's ergonomics, declared
properly instead of scripted.

Target: Lenovo ThinkPad T490s.

## What it is and is not

**Is:** a flake you clone and build on a stock NixOS install. Hyprland,
Emacs and Neovim, Brave and Firefox, KeePassXC, a full devops toolchain, and
a security posture that is written down rather than assumed.

**Is not:** an ISO. That was considered and deliberately shelved. Standard
NixOS install, then this flake, is less work to build, less work to maintain,
and more idiomatic for Nix.

## Differences from omarchy-nix

| | omarchy-nix | Nyx |
|---|---|---|
| Editor | Neovim | Emacs (daemon) + Neovim |
| Browser | Chromium | Brave with managed policy, Firefox alongside |
| Passwords | 1Password | KeePassXC, local kdbx |
| Assistant | ChatGPT wrapper | Claude Code |
| DNS | system default | Quad9 over TLS with DNSSEC |
| Secrets | none | sops-nix |
| Secure Boot | none | lanzaboote, wired but opt-in |
| MAC | static | randomised per connection |
| sudo | sudo | sudo-rs, wheel-only |
| MAC/LSM | none | AppArmor, auditd |

## First build

On a freshly installed NixOS 26.05 machine:

```
# 1. Get the repo
nix-shell -p git --run 'git clone <your-remote> ~/nyx'
cd ~/nyx

# 2. Generate the real hardware config
sudo nixos-generate-config --show-hardware-config > hosts/t490s/hardware-configuration.nix

# 3. Fill in the CHANGE-ME fields
#    - home/default.nix: git userEmail, signing key
#    - modules/security.nix: leave lanzaboote and TPM commented for now

# 4. Build without switching, so a failure costs you nothing
sudo nixos-rebuild build --flake .#nyx-t490s

# 5. If it builds, switch
sudo nixos-rebuild switch --flake .#nyx-t490s
```

## Post-install, in order

1. Boot, confirm Hyprland, wifi, audio, brightness, suspend.
2. Create the KeePassXC database on the encrypted root.
3. `age` key and `sops` secrets file, then uncomment the sops block and
   move to declarative user passwords.
4. `sbctl` key creation and enrolment, then enable lanzaboote.
5. Only after step 4: `systemd-cryptenroll` for TPM2 unlock.

Steps 4 and 5 are the ones that can leave you with an unbootable machine.
Do them on a day when you have time and a live USB in your pocket.

## Known rough edges

- `nixos-hardware.nixosModules.lenovo-thinkpad-t490s` may not exist under
  that exact attribute name. If the flake errors on it, check the
  nixos-hardware repo for the correct T490s path, or fall back to
  `lenovo-thinkpad-t480s` plus `common-pc-laptop`, which is close enough.
- `thunderbolt` is blacklisted in `modules/security.nix`. If you use a dock,
  remove that line.
- `users.mutableUsers = false` is set but the hashed password file is still
  commented out. Do not switch to `false` behaviour and reboot until you have
  a declared password, or you will lock yourself out.
- Claude Code is pulled from unstable via the overlay. It moves fast and
  stable will lag.
