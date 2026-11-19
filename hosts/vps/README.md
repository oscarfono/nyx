# The server — how to build it, what is unverified, and what comes after

This directory is one entry in `nixosConfigurations`. The box is rented from
Vultr, and it exists to be the machine that *works* — the agent, the hub, the
floor, the night shift — while the T490 stays the machine that *holds the keys*.

That split is a decision, not a preference, and it is written up in the vault:
`policies/09-encryption-and-exposure.org` has the register of what each machine
holds and therefore whether it is encrypted.

---

## What is UNVERIFIED, and it is most of it

Everything in this directory was written on **19 November 2026**, in the agent's
sandbox, which **has no Nix installed**. **None of it has ever been evaluated.**
This is the same limit that was recorded for `liber8-floor/nix/package.nix`, and
the same rule applies: an artefact that cannot be tested where it is written has
to say so itself and name the command that tests it.

**The command that settles it**, from the T490:

```bash
nixos-rebuild build --flake ~/Projects/nyx#vps
```

It evaluates, builds and does **not** switch. It will name any option it does not
recognise. Run it before the box is worth anything.

### Verified, read from source on the day it was written

| what | where it was read |
|---|---|
| `disko` is consumed as `inputs.disko.nixosModules.disko` | `nix-community/disko` `flake.nix`: `nixosModules.disko = ./module.nix;` |
| the disko schema for a GPT disk with an ESP and a LUKS root | `disko/example/simple-efi.nix` and `disko/example/luks-interactive-login.nix` |
| that a LUKS volume with **no** `keyFile` and **no** `passwordFile` prompts for the passphrase | the same examples — `luks-interactive-login.nix` passes a file, its comment says the file is for *interactive login*; omitting both is the prompt |
| the initrd SSH options: `enable`, `port`, `shell`, `hostKeys`, `ignoreEmptyHostKeys`, `authorizedKeys`, `authorizedKeyFiles`, `extraConfig` | `nixpkgs/nixos/modules/system/boot/initrd-ssh.nix` |
| the Matrix modules exist (`mautrix-telegram` included) | `nixpkgs/nixos/modules/services/matrix/` |
| `mautrix-telegram`'s options: `settings`, `environmentFile`, `serviceDependencies`, `registerToSynapse` (which defaults to auto-registering with Synapse) | `nixos/modules/services/matrix/mautrix-telegram.nix` |
| that `nixos-anywhere` installs over SSH by kexec, partitions with disko, and **overwrites the target** | its own README |

### Assumed, and therefore to be checked before it matters

1. **That Vultr is KVM.** It is not stated in anything read for this file. The
   check is on the running image: `systemd-detect-virt` should say `kvm`. If it
   says `openvz` or `lxc`, **stop** — NixOS cannot be installed on it at all.
2. **That the instance boots EFI.** See the firmware check below.
3. **The exact flag name for supplying the LUKS passphrase to `nixos-anywhere`.**
   Its documentation says it can upload disk encryption secrets; the flag name is
   not quoted here because it was not read. Confirm it on the machine that runs it:
   `nix run github:nix-community/nixos-anywhere -- --help`.
4. **That `services.qemuGuest`, `fail2ban`'s `jails.sshd.settings` shape, and
   `boot.loader.efi.canTouchEfiVariables` accept exactly what is written here.**
   `nixos-rebuild build` is what says.

---

## At the order screen

| field | value | why |
|---|---|---|
| image | **Debian 12** | it is about to be destroyed; anything that boots and kexecs will do |
| region | **Singapore** | closest well-connected hub to Phuket |
| plan | `voc-g-4c-16GB-80s` | **verify the price**: the same 4 vCPU / 16 GB shape appears on Vultr's own pricing page at around $120/month and, as a replica-node variant, at **$600**. That difference is worth checking twice |
| custom ISO | **none** | the ISO route is the fallback, not the plan. Vultr's documentation says they no longer support NixOS first-party and points at custom ISOs; that path needs a public, direct, redirect-free URL under 10 GB and then a VNC session unless the ISO is custom-built with a key baked in |
| SSH key | **paste the Director's public key at creation** | it is the only way in, and Debian's cloud image installs it |

## Before installing — two checks, one minute

On the fresh Debian image, over SSH:

```bash
systemd-detect-virt          # must say: kvm
ls /sys/firmware/efi         # a listing means EFI: this directory is correct.
                             # "No such file or directory" means LEGACY BIOS:
                             # read the note at the top of disko.nix first.
```

## The install

From the **T490**, which has Nix and the flake:

```bash
# 0. THE FIRST STEP, and it is not optional: the flake gained a `disko` input,
#    and flake.lock has no revision for it until the lock is refreshed. Until
#    then the flake does not evaluate at all and the error names `disko`.
nix flake update --flake ~/Projects/nyx
nixos-rebuild build --flake ~/Projects/nyx#vps     # prove it evaluates first

# 1. the unlock passphrase, in a file the installer can read and nothing else
#    should (delete it afterwards; do not commit it)
umask 077; read -rs -p "LUKS passphrase: " k; echo; printf '%s' "$k" > /tmp/luks.key; unset k

# 2. put the Director's public key into hosts/vps/default.nix where the
#    placeholder is — the initrd unlock uses that line and nothing else.

# 3. install
nix run github:nix-community/nixos-anywhere -- \
  --flake ~/Projects/nyx#vps \
  --disk-encryption-keys /tmp/luks.key /tmp/luks.key \
  root@<the-new-ip>

# 4. remove the local copy
shred -u /tmp/luks.key
```

> `--disk-encryption-keys` is the shape recorded in nixos-anywhere's docs, with
> the flag name **to confirm with `--help`** (see the assumed list). If the flag
> differs, only this line changes.

**Then the box reboots and appears to be dead.** It is not: the passphrase is
being waited for.

```bash
ssh -p 2222 root@<ip>        # type the passphrase, and the boot continues
```

Two things that are normal here and must not be "fixed":

- **No ping, no port 22, no service** until the passphrase is typed. The initrd
  is a minimal environment: it has no network until it has a root filesystem to
  finish booting into.
- **"REMOTE HOST IDENTIFICATION HAS CHANGED"** on every unlock. The initrd's host
  keys are generated per boot unless set explicitly, so they change every time.
  It is expected. Do not add it to `known_hosts` properly and do not "resolve" it.

## After the install

```bash
ssh coops@<ip>               # the system's own SSH, on 22, keys only
sudo nixos-rebuild switch --flake ~/Projects/nyx#vps
```

Then, and only then, the machine is ready for what it is for.

---

## The hub — what it is, and the two things it needs that are not code

`modules/matrix.nix` now holds the Matrix hub: Synapse with federation and
registration both off, the Telegram bridge with it, nginx in front, ACME for
certificates, and the discovery file at the root domain. Also unbuilt, and the
same command settles it.

**Two decisions are baked into it, and one of them is permanent:**

1. **`server_name` is `designandweb.ltd`.** It appears at the end of every user
   ID and room address (`@coop:designandweb.ltd`) and it is the one value here
   that cannot be changed later — changing it makes every address anyone has
   written down a stranger. The homeserver itself lives at
   `matrix.designandweb.ltd`, joined to the address by a small file served from
   the root domain. **Consequence: the machine is movable.** Rebuild it in
   another country, repoint the DNS, and no MXID changes.
2. **Federation and registration are off**, by not serving them rather than by a
   policy the software is asked to enforce.

**What it needs from you that is not code:**

- **Two DNS records**, both pointing at the box:
  - `matrix.designandweb.ltd` — A record. The homeserver.
  - `designandweb.ltd` — A record. It serves the discovery file today and the
    company site later, so it must reach this machine until that site exists.
- **One open question, and it is a secret, not a preference:** the bot account
  has to be created, registration is off, and the documented tool needs a
  `registration_shared_secret` — which must NOT go in the Nix store. The module
  names three ways to resolve it and the first thing to check:
  `nixos-option services.matrix-synapse | grep -i secret`.

**And the thing that must not be forgotten once it runs:** `/var/lib/matrix-synapse`
holds the server's **signing key**. Lose it and every client sees a different
server at the same address. Policy 09 rule 5 requires it backed up off this
machine, and `modules/backup.nix` is written for the laptop's paths — it does
not cover this box yet. That is the change after this one.

## The one thing that must not be assumed later

**The T490 must keep the `age` key and the signing key.** The moment this box
holds the company's API keys — which it does, as soon as the agent runs on it —
the only copy of anything that decrypts the backups must be off it. That is
policy 09's open question 1, and it is still open.
