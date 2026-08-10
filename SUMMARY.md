# Nyx — project summary

## What Nyx is

**Nyx** ("Not Your X") is my standalone, security-first NixOS desktop config
for a Lenovo ThinkPad T490, hostname `beta`, user `coops`. It takes the
*idea* of Omarchy and rebuilds it the way NixOS wants it built: declarative
modules, no install scripts, no runtime mutation.

It is not a wrapper around anyone else's config. Repo:
`github.com/oscarfono/nyx`. Working copy: `~/Projects/nyx`.

Layout is in README.md. How to do things is in CHEATSHEET.md. Workarounds
and when to retest them are in KNOWN-ISSUES.md. This file is state,
decisions and lessons.

## Status: installed and working

LUKS root · Secure Boot enforcing with my own keys · sops-nix secrets with
declarative passwords · restic to Exoscale, daily · Hyprland (Lua config) ·
Waybar · fuzzel · walker menus · Ghostty · zsh · Emacs daemon with
straight.el · swaybg · Quad9 DNS · Bluetooth · Steam · voice dictation ·
secops toolkit with metasploit on local postgres · `nyx-doctor`.

**Suspend measured:** 85% → 79% over 8h26m in S3, about 0.7%/hour. Roughly
six days suspended on a full charge. Clean resume, wifi survived.

Untested: external displays, dock, fingerprint reader.

## Decisions, and why

| Decision | Reasoning |
|---|---|
| Flake and config repo, no ISO | The installer was 80% of the work for 20% of the value. |
| `nixos-unstable` | Hyprland and desktop tooling move fast. |
| Emacs with straight.el | Nix owns the binary and toolchain; straight owns all elisp. Two package managers on one load-path is the failure mode. |
| Brave default, Firefox alongside | Chromium engine accepted knowingly; de-Googling here is about services, not the engine. Locked down via managed policy. |
| Hyprland config as **Lua**, hand-generated | hyprlang is deprecated as of 0.55 and goes away in 0.57. home-manager's serialiser emits invalid Lua, so we write it ourselves from Nix data. |
| Every Lua bind in `pcall` | An error before the binds means NO binds and emergency mode. `pcall` costs one bind instead of the session. |
| swaybg, not hyprpaper | hyprpaper reported "monitor has no target" while its IPC rejected every request. swaybg has no IPC: write path, restart unit. |
| Native postgres for metasploit, not a container | On a declarative system the isolation argument evaporates: service, database, user and permissions are all in one file. A container would add an image to pin and a volume to back up separately. |
| Tray applets for wifi and bluetooth, no Waybar modules | One indicator per thing. The applets carry state *and* a click menu; the modules only carried state. |
| opentofu, not terraform | Terraform is BSL 1.1. `terraform=tofu` alias covers muscle memory. |
| Unfree allow-listed per package | One list, in `apps.nix`. It doubles as the inventory: brave, claude-code, steam, burpsuite. |
| Personal shell functions outside the repo | `~/.config/zsh/local/*.zsh`, sourced but unmanaged. Backed up by restic, since nothing else has them. |

## Multiple machines

`flake.nix` defines `mkHost`. A new machine is an entry in
`nixosConfigurations`, not a fork: `hostName`, `username`, `hardware`,
`hostPath` and the module list are all arguments. Untested — there is only
one machine so far.

## Keybindings

`SUPER+T` terminal · `SUPER+E` Emacs · `SUPER+B` Brave · `SUPER+SHIFT+B`
Firefox · `SUPER+P` KeePassXC · `SUPER+N` files · `SUPER+C` calculator ·
`SUPER+A` Claude Code · `SUPER+D` dictation · `SUPER+Space` launcher ·
`SUPER+ALT+Space` menu · `SUPER+K` cheatsheet · `SUPER+Q` close ·
`SUPER+Return` maximise · `SUPER+F` fullscreen · `SUPER+V` float ·
`SUPER+arrows` focus · `SUPER+SHIFT+arrows` move · `SUPER+CTRL+arrows`
resize · `SUPER+1-9` workspaces · `SUPER+SHIFT+C` caffeine ·
`SUPER+SHIFT+L` lock · `Print` region · `SHIFT+Print` to satty ·
`SUPER+Print` window · `CTRL+Print` screen · `SUPER+SHIFT+S` save ·
`SUPER+SHIFT+R` record.

Menu sections: Style, Capture, Tools, Network, Nix, System, Session, Learn.

## Security posture

**Boot:** Secure Boot enforcing, signed with my own keys via lanzaboote
v1.1.0. `bootctl status` reports `Secure Boot: enabled (user)`. Keys in
`/var/lib/sbctl`, backed up on the vault USB. TPM2 is not available on this
machine, so LUKS takes a passphrase at every boot — the right trade anyway.

**Secrets:** two recipients in `.sops.yaml` — the host SSH key (so sops-nix
can decrypt at activation) and my personal age key (so I can edit as
myself). `users.mutableUsers = false`; the password comes from
`/run/secrets-for-users/coops-password`, so `passwd` is a no-op.

**Network:** Quad9 over TLS with `Domains = "~."`, so no query ever reaches
a DHCP-supplied resolver. Currently `opportunistic`/`allow-downgrade` —
tightening while living in hotels is asking for trouble.

**Backups:** restic to Exoscale Geneva, daily, incremental, client-side
encrypted, 7 daily / 5 weekly / 12 monthly. Bucket has versioning and object
lock, so a compromised laptop cannot delete its own snapshots.

**Vault USB:** LUKS2, in a safe deposit box. Holds the age key, restic
password and S3 credentials, GPG key, SSH keys, sbctl keys, the LUKS header
backup, KeePassXC databases, and a README explaining what each unlocks.

## Hard-won lessons (do not relearn these)

1. **Nothing network-dependent in a home-manager activation script.** It
   runs before the network and under `set -e`; a failed `git clone` aborted
   the entire user config. Use a `systemd.user.service` after
   `network-online.target` that swallows its own failures.
2. **Set `home-manager.backupFileExtension`.** One stray pre-existing file
   blocked all of activation.
3. **`nixos-rebuild test` does not survive a reboot.** Compare
   `readlink -f /run/current-system` with
   `readlink -f /nix/var/nix/profiles/system`.
4. **Run `passwd` after install.** Not doing so cost a full reinstall:
   `pam_unix: auth could not identify password` means no hash exists, and no
   generation can fix it because they share `/etc/shadow`.
5. **Flakes read the git index.** Edit without `git add` and Nix evaluates
   the old state. "Path does not exist in Git repository" means exactly this.
6. **A running service predates the config that replaced it.** Restart the
   unit before debugging.
7. **`FallbackDNS` is only consulted when no other DNS is configured.**
   Quad9 belongs in `DNS` with `Domains = "~."`. Strict DNSSEC plus strict
   DNSOverTLS against a DHCP resolver breaks every lookup.
8. **Nix wants a semicolon after every attribute**, including the last.
9. **In `''` strings, `''` is the escape character.** It cannot appear
   literally — not even inside a comment within the string.
10. **Nested quoting (Nix → Lua → shell) is where configs break.** If a
    command needs quotes or `$(...)`, put it in a script in `home/tools.nix`
    and call the script.
11. **Inside `home.file."....lua".text`, comments are Lua (`--`), not Nix.**
12. **`allowUnfreePredicate` is a function, not a list.** A second
    definition replaces the first rather than merging.
13. **home-manager's gtk module writes the same dconf keys you might set by
    hand.** Two different values is a hard conflict.
14. **sops `neededForUsers` secrets land in `/run/secrets-for-users`.**
15. **Secrets are 0400 root; `sudo -E` does not help** because sudo drops
    the environment. Source the env file *inside* the root shell:
    `sudo sh -c 'set -a; . /run/secrets/x; set +a; cmd'`.
16. **PostgreSQL 15+ revokes CREATE on the public schema.** Metasploit
    connects, fails to create its tables, then errors on every query.
    `ALTER DATABASE ... OWNER` and `ALTER SCHEMA public OWNER`.
17. **`$PSQL` is not defined in a `postStart` hook** you write yourself.
    Use the package path.
18. **Never `sbctl sign` anything lanzaboote manages.** Signing appends
    bytes, changing the hash the UKI stubs check. Every generation then
    panics with `Kernel hash does not match`.
19. **`/boot/EFI/nixos/kernel-*.efi` showing unsigned is CORRECT.** It is
    the raw kernel the stub loads, not part of the signature chain. Do not
    sign it, do not delete it.
20. **ThinkPad firmware sets the immutable attribute on efivars.**
    `chattr -i` the KEK and db entries before `enroll-keys`. Resets each
    boot. The firmware also hangs on the splash after any Secure Boot state
    change — power-cycle once before assuming failure.
21. **`nh clean` prunes the store, not the ESP.** Without an ExecStartPost
    of `switch-to-configuration boot`, `/boot` fills with UKIs for
    generations that no longer exist.
22. **Ghostty exports `GHOSTTY_RESOURCES_DIR` into the session,** so Emacs
    inherits it and home-manager's zshrc loads Ghostty's shell integration
    inside `eat`. Guard on `$TERM`, not on the file existing.
23. **The Hyprland Lua function is `hl.window_rule`, with an underscore,**
    and class matching is a regex. `pcall` swallowed the wrong name
    silently.
24. **Fractional monitor scaling upsamples XWayland clients.** Steam looked
    like a stretched JPEG until `xwayland.force_zero_scaling`.
25. **A dialog can have a different WM class from its parent.** KeePassXC's
    unlock window is `keepassxc`, not `org.keepassxc.KeePassXC`.
26. **The vault paid for itself within a day.** SSH keys vanished from
    `~/.ssh` for reasons never established; restored in two minutes.

## Next actions

- [ ] Test a real restore via `nyx-backup mount`, not just `.ssh`.
- [ ] Tighten DNS to strict once I am off hotel wifi.
- [ ] Package melancholy properly: the `.tmTheme` upstream to bat, the
      palette somewhere it gets used by someone other than me.
- [ ] File the Waybar workspace-click issue (see KNOWN-ISSUES.md).
- [ ] External displays, dock, fingerprint reader.
- [ ] A second host, once I am reunited with my belongings.
