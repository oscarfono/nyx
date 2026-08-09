# Nyx cheatsheet

Everything here assumes the repo is at `~/Projects/nyx` and the host is `beta`.

## The loop

```bash
cd ~/Projects/nyx
$EDITOR modules/whatever.nix
git add -A                 # flakes read the git INDEX, not the worktree
sudo nixos-rebuild switch --flake .#beta
```

`git add -A` is not optional. Forget it and Nix silently evaluates the old
file and you debug a change that was never applied.

## Rebuild variants

| Command | Effect |
|---|---|
| `nixos-rebuild build --flake .#beta` | Build only. Nothing changes. Safe. |
| `nixos-rebuild test --flake .#beta` | Apply now, do NOT add to boot menu. Reverts on reboot. |
| `nixos-rebuild switch --flake .#beta` | Apply and make default. |
| `nixos-rebuild boot --flake .#beta` | Apply at next boot only. |
| `nixos-rebuild switch --rollback` | Back to the previous generation. |

Use `test` for anything risky. If it locks you out, reboot and you are back.

## Installing a package

There is no `install` command. You edit a file and rebuild.

- System-wide (all users, needs sudo to change):
  `modules/apps.nix` → `environment.systemPackages`
- Just you: `home/default.nix` → `home.packages`
- Try before committing: `nix shell nixpkgs#ripgrep` (ephemeral, gone on exit)
- Find the name: `nix search nixpkgs ripgrep`, or https://search.nixos.org

Unfree packages must also be added to the allow-list in `modules/apps.nix`.
That list is deliberate: it is the complete inventory of non-free software
on the machine.

## Updating

```bash
cd ~/Projects/nyx
nix flake update                  # bump all inputs, writes flake.lock
sudo nixos-rebuild switch --flake .#beta
```

Update one input only: `nix flake update nixpkgs`.
Roll back an update: `git checkout flake.lock && rebuild`.

## Generations and rollback

```bash
nixos-rebuild list-generations
sudo nixos-rebuild switch --rollback
```

Older generations are also in the boot menu. That safety net does NOT cover
LUKS, bootloader or `mutableUsers = false` changes — those can stop you
reaching the menu at all. Change boot or crypto alone, never alongside
anything else.

## Garbage collection

```bash
sudo nix-collect-garbage -d          # delete old generations, free space
nix store gc
```

`-d` removes rollback targets. Do not run it until the current generation
has proven itself.

## Adding a host

`flake.nix` has `mkHost`. A new machine is an entry, not a fork:

```nix
gamma = mkHost {
  hostName = "gamma";
  username = "coops";
  hardware = null;                    # or a nixos-hardware module
  hostPath = ./hosts/desktop;
  modules = desktopModules;           # drop desktop.nix/fonts.nix if headless
};
```

Then on that machine:
```bash
sudo nixos-generate-config --show-hardware-config > hosts/desktop/hardware-configuration.nix
git add -A && sudo nixos-rebuild switch --flake .#gamma
```

## When something breaks

```bash
journalctl -b -p err --no-pager | tail -40      # this boot's errors
journalctl -u NAME -n 50                        # a system service
journalctl --user -u NAME -n 50                 # a user service
systemctl --user status                         # what failed for you
hyprctl reload                                  # reload Hyprland config
```

`Ctrl+Alt+F2` gets a TTY when the desktop is unusable. `Ctrl+Alt+F1` returns.

## Nix language traps

- Semicolon after **every** attribute, including the last in a set.
  `syntax error, unexpected '}'` means look at the line above.
- Inside `''...''` strings, `''` is the escape character. `''${` is a literal
  `${`. An empty `''` cannot appear, not even in a comment inside the string.
- Nested quoting (Nix → Lua → shell) is where configs break. If a command
  needs quotes or `$(...)`, put it in a script in `home/tools.nix` and call
  the script from the keybind.

## Secrets

`sops-nix` decrypts at activation into `/run/secrets`, never into the
world-readable Nix store.

```bash
sops secrets/secrets.yaml            # edit, re-encrypts on save
mkpasswd -m yescrypt                 # generate a password hash to store
```

## Keybindings

`SUPER+K` shows the full list.
