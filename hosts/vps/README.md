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

## 20 November 2026 — the box is ordered, and the bootloader changed because of it

The Director ordered **`vx1-g-4c-16g-240s` in Tokyo** (region `nrt`). Three things
changed from the shape this directory was written against, and each is now reflected
in the files.

**1. VX1, and it is a better box for less money than the one we costed.** Vultr's own
pricing page states VX1 uses **dedicated CPU resources** — not shared, which one
third-party comparison site claims and is wrong — and lists 4 vCPU / 16 GB / **240 GB
NVMe** at **$0.153/hour**, billed on actual hours and explicitly "not capped at 672
hours", so a full 744-hour month is about **$113.83**. The General Purpose plan we had
specified (`voc-g-4c-16gb-80s`, 4 vCPU / 16 GB / 80 GB) is **$120/month** on the same
page. So the deliberate choice is: **cheaper, three times the disk, dedicated cores,
newer silicon.** The 240 GB matters on its own — `/nix` plus a build cache plus the
agent's working copies will eat an 80 GB disk, and the disk layout already takes
`size = "100%"` so it needs no change.

**2. Tokyo, not Singapore.** Region is a latency and jurisdiction choice for hardware,
not identity: the Matrix `server_name` is `designandweb.ltd` and the machine is movable,
so nothing in this directory depends on where the instance sits. Two honest notes. From
Phuket, Tokyo is roughly 90–110 ms and Singapore roughly 25–40 ms, so Singapore is the
snappier terminal — but Tokyo is comfortably workable and the mining clients are the
other direction anyway, in Australia. And the region is not the jurisdiction question
people assume: Vultr is a United States company, so its account data is exposed to
United States process wherever the disk is racked.

**3. The bootloader is no longer a guess.** `default.nix` was written for systemd-boot
on EFI. Vultr's own custom-image documentation says the image must match "either Legacy
(BIOS) or UEFI", and a published Vultr + NixOS account reports UEFI/GPT not being
supported there at all. An install that guesses wrong does not come back. So the host
now uses **GRUB with `efiSupport = true` and `efiInstallAsRemovable = true`**, which
installs into the MBR and the bios_grub partition for BIOS *and* into the ESP for UEFI
from one build command, and `disko.nix` now declares the 1 MiB `EF02` bios_grub
partition that the BIOS path needs. The layout is disko's own `example/hybrid.nix`
verbatim plus the LUKS wrapper. `efi.canTouchEfiVariables` is **false**: this guest's
NVRAM belongs to the provider and a boot entry written there may not persist, which is
exactly when GRUB's removable path is the right answer.

**Still do this first, on the stock image, before anything is installed:**

```sh
ls /sys/firmware/efi       # a listing = EFI;  "No such file or directory" = BIOS
lsblk                      # must name exactly ONE disk, and it must be /dev/vda
```

Either firmware answer is now safe. Knowing which one you got still matters, because it
is what tells you whether `/boot` is being read from the ESP.

**No custom ISO, and the question is closed.** Vultr does support uploading one (public
URL, under 10 GB, two per account) — and the plan does not use it. The install is
Debian from Vultr's own menu, then one `nixos-anywhere` run from the T490, which
`kexec`s into a NixOS installer and partitions with disko. An ISO adds a boot-mode
setting to get wrong and buys nothing.

**What is still unverified, and it is the honest list:** neither file has been evaluated
(`nixos-rebuild build --flake ~/Projects/nyx#vps` has not been run — there is no Nix in
the agent's sandbox), the flake needs `nix flake update` first because the new `disko`
input has no revision in `flake.lock`, the exact `nixos-anywhere` flag for supplying the
LUKS passphrase is still to be read from `--help` on the machine that runs it, and the
GRUB-hybrid layout is taken from disko's example rather than from a completed install on
this box.

## 20 November 2026, later — the provider is DigitalOcean now

Vultr kept failing, so the target moved to **DigitalOcean**. Nothing about the design
changes: the same Debian image, the same `nixos-anywhere` from the T490, the same disk
layout, the same encryption. Four things are worth writing down, and one of them makes
an earlier change load-bearing rather than cautious.

**1. The GRUB hybrid layout is now required, not belt-and-braces.** DigitalOcean's own
custom-image documentation says, in its limits section: *"UEFI boot is not supported.
Custom images must boot using BIOS."* and *"ISO images are not currently supported."* So
a Droplet is a **BIOS** machine and there is no ISO path to hide behind. The change made
earlier today — GRUB with `efiSupport` and `efiInstallAsRemovable` plus the 1 MiB `EF02`
bios_grub partition — is the thing that makes this box boot at all. Had it been left as
systemd-boot on EFI, the install would have completed and the machine would not have
come back, which is precisely what the old comment warned about.

**2. The guest profile was missing and is now imported.** `hosts/vps/default.nix` did not
import `${modulesPath}/profiles/qemu-guest.nix`. It does now. That profile brings the
virtio disk and network drivers into the **initrd** and turns on DHCP, and without it a
hardened system can install cleanly and then come up unable to find its own disk or its
network, because the installer's initrd carries drivers the installed system does not.
Published accounts of `nixos-anywhere` on DigitalOcean specifically report having to sort
out networking by hand; DHCP plus this profile is the answer to that, and the Recovery
Console is the fallback if it still goes wrong. **The disk device stays `/dev/vda`**,
which is what a DigitalOcean virtio droplet uses.

**3. The shape changed, and not in our favour.** DigitalOcean's prices, from its own
pricing page:

| plan | vCPU | RAM | disk | $/mo | note |
|---|---|---|---|---|---|
| General Purpose (**dedicated**) | 4 | 16 GB | **50 GiB** | **$126** | NVMe on the Premium variant, 10 Gbps out |
| General Purpose (dedicated) | 8 | 32 GB | 100 GiB | $252 | |
| Basic (shared) | 8 | 16 GiB | 320 GiB | **$96** | shared CPU, regular SSD |
| Basic (shared) | 4 | 8 GiB | 160 GiB | **$48** | |

The comparison is worth stating plainly: Vultr's `vx1-g-4c-16g-240s` was **$113.83** for
4 dedicated vCPU / 16 GB / **240 GB NVMe**. DigitalOcean's nearest equivalent is **$126
for 4 vCPU / 16 GB / 50 GiB** — more money for a fifth of the disk. Disk is the resource
this box actually grows into: `/nix`, a build cache and the agent's working copies. So
the desk's read: **the $96 shared 8 vCPU / 16 GiB / 320 GiB is the better buy for this
workload** (a chat agent, a Matrix hub, occasional Nix builds — bursty, not sustained),
and if dedicated cores are wanted then it is $126 and a Volume later. DigitalOcean also
now offers **v5 configurable droplets** where vCPU, memory and storage are chosen
separately, which would be the ideal shape; its rates are not published in the tables
that were read, so the configurator's live running total is the authority.

**4. THE SAME TRAP, AND IT IS THE ONE THAT BURNED US.** DigitalOcean sets **resource
limits per team**, and a new account starts low:

| tier | droplets | what it can create |
|---|---|---|
| Tier 1 | 3 | Basic shared CPU, **up to $48** |
| Tier 2 | 10 | Basic shared up to $56, some dedicated up to $84 |
| Tier 3 | 15 | all Basic shared, dedicated up to $163 |
| Tier 4 | 25 | all droplets |
| Tier 5 | 100 | all droplets |

A brand-new account may therefore **refuse the $96 or $126 droplet** until there is
billing history or a support ticket, which is exactly the shape of the Vultr failure.
The two ways through it: order the **$48 Basic (8 GiB / 4 vCPU / 160 GiB)**, which fits
Tier 1 and is genuinely enough to start — and lodge the limit-increase ticket *before*
the bigger box is needed rather than on the day it is. Community reports are mixed on
how readily DO grants increases to accounts with no billing history.

**Also settled: no agent product.** DigitalOcean's "agent" offering is **Gradient**, a
hosted agent builder and serverless inference layer billed per token. It is not this.
Our agent is Hermes running on a machine we own, described by a flake, backed up by
restic to our own bucket, with our own sandbox, tools and cron. A hosted agent runtime
would mean renting someone else's process, paying by the token, and giving up the
rebuild, the backup and the key custody in one move. **A plain Droplet with Debian 12,
and not a Marketplace one-click image either** — we replace the operating system.
