# NixConfig

One flake, every machine. A bare-metal desktop, a couple of QEMU dev
VMs, a VirtualBox guest, a WSL distro, and a plain Home Manager setup on
a non-NixOS laptop all come out of this single repository — each one
described by a handful of lines in a profile dictionary rather than its
own copy-pasted config tree.

Most of the interesting machines are **impermanent**: `/` is thrown away
on every boot and rebuilt from the store, and only paths you've
explicitly declared survive. That sounds dramatic; in practice it means
the system can't accumulate mystery state, and anything that breaks is
one reboot away from being gone.

This file is the entry point. It explains how the repo is put together,
what's in it, and the commands you actually type day to day. Longer
one-time runbooks live in [`docs/`](#documentation-index).

---

## Contents

- [How this repo works](#how-this-repo-works)
  - [Four principles](#four-principles)
  - [How a profile is assembled](#how-a-profile-is-assembled)
  - [Repository map](#repository-map)
- [The machines](#the-machines)
- [Daily commands](#daily-commands)
  - [Rebuilding](#rebuilding)
  - [Maintenance](#maintenance)
  - [Reloading Plasma after a rebuild](#reloading-plasma-after-a-rebuild)
  - [Shell cheat sheet](#shell-cheat-sheet)
- [Pinning a package version](#pinning-a-package-version)
- [Secrets (agenix)](#secrets-agenix)
- [Running the VMs](#running-the-vms)
- [Impermanence in one page](#impermanence-in-one-page)
- [Creating a new profile](#creating-a-new-profile)
- [Installing a bare-metal machine](#installing-a-bare-metal-machine)
- [Adding a module](#adding-a-module)
- [Ephemeral shells: `ns`](#ephemeral-shells-ns)
- [Dev and agent tooling](#dev-and-agent-tooling)
- [Documentation index](#documentation-index)

---

## How this repo works

### Four principles

These four ideas explain nearly every layout decision in the repo.
[`CONTRIBUTING.md`](CONTRIBUTING.md) covers them in depth.

**1. One flake, many profiles.** Every machine is a *profile* — a small
attrset in [`nixos/profiles.nix`](nixos/profiles.nix) saying what you
want (hostname, hypervisor, impermanence yes/no, a few extras).
[`nixos/lib/mk-profile.nix`](nixos/lib/mk-profile.nix) turns each entry
into a real `nixosSystem`. `flake.nix` is just inputs and outputs glue.

**2. NixOS modules and Home Manager modules are separate concerns, and
the directory tree enforces it.** System-level config lives in
`modules/nixos/`, user-level in `modules/home/`. A module belongs to
exactly one of them. When a feature genuinely has both halves — fish, for
instance — it goes in `modules/dual/` and detects which evaluator it's
running under.

**3. Impermanence is a property of the running system, not a
filesystem.** It's a wipe mechanism plus a list of paths preserved under
`/nix/persist`. Any disk layout works as long as `/nix` and `/boot`
survive the wipe, which is why the same `impermanence = true` flag works
on a tmpfs-rooted VM and on a btrfs bare-metal box.

**4. Disko is opt-in through the host folder, not a flake flag.**
`disko.nixosModules.default` is loaded into every profile but stays
completely inert until a host folder imports one of the layouts in
`nixos/disko/`. Declaring a disk layout is a per-machine decision, so it
lives with the machine.

### How a profile is assembled

Each profile is built from five ingredients, in this order:

| # | Ingredient | Where |
|---|---|---|
| 1 | `commonNixosModules` — the system baseline every profile gets | `flake.nix` |
| 2 | `commonHomeImports` — the user baseline (`home.nix`) | `flake.nix` |
| 3 | The host folder, auto-discovered by name: `default.nix` → NixOS, `home.nix` → Home Manager | `nixos/hosts/<profile>/` |
| 4 | The impermanence flag — also pulls in `modules/home/persistence.nix`, and `wipe-root.nix` on bare metal | `nixos/lib/mk-profile.nix` |
| 5 | `extraNixosImports` / `extraHomeImports` plus the module for `hypervisor` | `nixos/profiles.nix` |

The fields you can set on a profile:

| Field | Required | Default | Notes |
|---|---|---|---|
| `hostname` | yes | — | Becomes `networking.hostName` |
| `hypervisor` | yes | — | `qemu`, `wsl`, or `none`. Anything else throws |
| `graphics` | no | `true` | Only consumed by QEMU profiles |
| `impermanence` | no | `false` | Wipes `/` on boot; see [Impermanence](#impermanence-in-one-page) |
| `extraNixosImports` | no | `[]` | Setting this *replaces* what `sharedDesktopProfile` provided |
| `extraHomeImports` | no | `[]` | |

`sharedDesktopProfile` is sugar for "give me KDE Plasma", merged in with
`// { … }`.

### Repository map

```text
flake.nix                  inputs, outputs, overlays — glue only
pins.nix                   package version pin table  → see Pinning
home.nix                   Home Manager baseline
configuration.nix          safety net: fails loudly if you rebuild non-flake

nixos/
  profiles.nix             ★ the profile dictionary — start here
  base.nix                 system baseline: users, SSH, persistence, GC
  lib/mk-profile.nix       profile attrset → nixosSystem
  modules/                 profile-options, secrets, wipe-root
  platforms/               vm-qemu.nix, wsl.nix
  disko/                   single-disk-uefi.nix (btrfs), single-disk-bios.nix
  hosts/<profile>/         per-machine config, auto-discovered by name

modules/
  home/                    Home Manager modules (dev, gaming, network, …)
    dev/                   claude-code, cursor, dbhub, agent-sources, dmux
  nixos/                   NixOS modules (KDE suite, …)
  dual/                    works under both evaluators: fish.nix, ns/

secrets/                   agenix: secrets.nix (recipients) + *.age
scripts/                   VM launchers, appimage hash helper
githooks/pre-commit        auto-rekeys secrets when recipients change
docs/                      long-form runbooks and specs
```

---

## The machines

Everything below is a key in [`nixos/profiles.nix`](nixos/profiles.nix)
and a valid `--flake .#<name>` target.

| Profile | Hypervisor | Impermanent | What it's for |
|---|---|:---:|---|
| `nixos-desktop` | none | ✅ | The real bare-metal desktop. KDE + gaming |
| `nixos-vm` | qemu | ✅ | Main QEMU dev VM. KDE + gaming |
| `nixos-vm-headless` | qemu | ✅ | Headless QEMU VM — no KDE, no graphics |
| `nixos-vm-bare-test` | none | ✅ | Harness that exercises the *bare-metal* wipe path inside QEMU |
| `nixos-vbox` | none | ❌ | VirtualBox guest, installed via `nixos-anywhere` |
| `nixos-wsl` | wsl | ❌ | The WSL distro |
| `_template-bare-metal` | none | ❌ | **Skeleton. Never deploy it.** Copy it — see [Creating a new profile](#creating-a-new-profile) |

A leading underscore means "skeleton only". There's also a Home
Manager-only output, `homeConfigurations.david`, for the non-NixOS
workstation.

Two things worth knowing: the QEMU profiles have **no host folder at
all** — their bootloader and filesystems come from
`nixos/platforms/vm-qemu.nix` — and `nixos-vbox` has no OVA build path,
because `nixos-anywhere` is the only supported way in.

---

## Daily commands

### Rebuilding

| Where you are | Command |
|---|---|
| Non-NixOS workstation (Home Manager only) | `home-manager switch --flake .#david` |
| A NixOS machine, rebuilding itself | `sudo nixos-rebuild switch --flake .#<profile>` |
| WSL | `nr` — the alias in `nixos/hosts/nixos-wsl/home/fish.nix` |
| Pushing to a remote machine | `sudo nixos-rebuild switch --flake .#<profile> --target-host <user>@<host> --use-remote-sudo` |
| Inside a QEMU VM (via the 9p share) | `sudo nixos-rebuild switch --flake /mnt/hmconfig#nixos-vm` |
| Just checking it evaluates | `nix eval ".#nixosConfigurations.<profile>.config.system.build.toplevel.drvPath"` |

Swap `switch` for `build` to dry-run without activating — that works
with `--target-host` too, which is the polite way to test a remote
change.

### Maintenance

```bash
# Update the nixpkgs input
nix flake update nixpkgs

# Manual garbage collection (a weekly --delete-older-than 7d GC is
# already declarative, in nixos/base.nix and home.nix)
nix-collect-garbage -d

# Repair the store. Reach for this after a build is killed mid-write, or
# on "Invalid argument" / "path is missing" errors — the WSL ext4.vhdx
# takes damage from abrupt Windows shutdowns.
sudo nix-store --verify --check-contents --repair

# Targeted version, when you already know the bad path
sudo nix-store --delete --ignore-liveness /nix/store/<hash>-<name>

# Dump current Plasma settings as Nix
nix run github:nix-community/plasma-manager

# Refresh an AppImage hash
./scripts/update-appimage-hash.sh "https://example.com/MyApp-x86_64.AppImage"
./scripts/update-appimage-hash.sh "https://example.com/MyApp-x86_64.AppImage" \
  --replace modules/home/gaming.nix "sha256-OLD_HASH"

# Enable the secrets auto-rekey hook (once per clone)
git config core.hooksPath githooks
```

Run `checks` in any shell for a health report: git identity, `gh auth`,
`nixos-anywhere` on PATH, the origin remote, your SSH key and agent,
and whether tailscaled is up and logged in as the expected account.

### Reloading Plasma after a rebuild

`nixos-rebuild switch` writes new Plasma config, but most components
only reread their files at startup. Pick the smallest reload that covers
what you changed — logging out is the last resort.

```bash
# Covers ~90% of edits:
qdbus org.kde.KWin /KWin reconfigure                  # KWin: rules, shortcuts, compositor
systemctl --user restart plasma-plasmashell.service   # panels, widgets, applets

# More surgical options:
kquitapp6 kded6 ; kded6 &                             # notifications, power, kscreen
kbuildsycoca6 --noincremental                         # service menus, .desktop entries
qdbus org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.reloadConfig
```

A full logout is genuinely required for display managers, autostart
entries, session environment variables and `~/.config/plasma-localerc`.

**Change not taking effect at all?** Home Manager runs with
`backupFileExtension = "bak"`, so it *renames* a pre-existing config
instead of overwriting it. A `~/.config/plasmashellrc.bak` sitting next
to a stale `plasmashellrc` means HM has been refusing to clobber the live
file since the very first deploy. Delete the live file and re-switch.

### Shell cheat sheet

Fish is the login shell everywhere (root included). The greeting prints
most of this, but here it is in writing.

| Key | Does |
|---|---|
| `ctrl-f` | Browse user-defined functions |
| `alt-a` | Browse aliases |
| `ctrl-r` | Search history (fzf.fish) |
| `ctrl-t` | Find files |
| `ctrl-g` | Attach a tmux session (sesh picker; `ctrl-x` inside kills one) |
| `**<tab>` | Glob suggestions |
| `ctrl-b S` | Same session picker, from inside tmux |

| Alias | Expands to |
|---|---|
| `l` / `la` / `ll` / `lt` | `eza` with sensible flags (`lt` = tree) |
| `pc` | Run pre-commit on files changed vs `origin/master...HEAD` |
| `checks` | `post_install_checks` — the health report above |
| `dnw` | `diffnav --watch` |
| `ghd` | `gh dash` |
| `j` | zoxide jump (**not** `z` — that name was taken by a fish plugin) |

---

## Pinning a package version

Sometimes nixpkgs moves a package somewhere you don't want to go.
[`pins.nix`](pins.nix) is the single table of every version you're
holding back: one entry per package, naming the nixpkgs commit that
ships the version you want. `flake.nix` turns the table into one
overlay, applied to both the Home Manager `pkgs` and every NixOS
profile — so a pinned `foo` is pinned everywhere `pkgs.foo` appears.

1. **Find the commit** that ships your version, at
   [nixhub.io](https://www.nixhub.io) or
   [lazamar.co.uk/nix-versions](https://lazamar.co.uk/nix-versions).

2. **Add the entry** to `pins.nix`, with a comment saying *why* — future
   you will want to know when the pin can be dropped:

   ```nix
   quarto = {
     # 1.7.34 — 1.8.x ships a jog.lua filter that can't traverse
     # pandoc's TableBody node, which breaks table rendering.
     rev = "5d6bdbddb4695a62f0d00a3620b37a15275a5093";
     hash = lib.fakeHash;
   };
   ```

3. **Let the build tell you the hash.** Rebuild with `lib.fakeHash` in
   place; the mismatch error prints the real value. Paste it in. (If you
   prefer to fetch it up front:
   `nix-prefetch-url --unpack https://github.com/NixOS/nixpkgs/archive/<rev>.tar.gz`.)

**This only pins backwards.** To get something *newer* than nixpkgs has,
there's no commit to point at — use `overrideAttrs` at the use site
instead. Precedent to copy from: `code-cursor` in `flake.nix`.

---

## Secrets (agenix)

Secrets are age-encrypted files committed to
[`secrets/`](secrets/), each encrypted to a list of recipients in
[`secrets/secrets.nix`](secrets/secrets.nix). Recipients are **SSH
public keys** — one per machine (its host key) plus your user key, so a
rekey can be driven from whichever machine you happen to be on. At boot,
a NixOS host decrypts its secrets with its host key and drops the
plaintext in `/run/agenix/<name>`.

Currently in use: the login password hash, a Tailscale auth key, and a
Cachix token.

> **Always `cd secrets` first, and always write `RULES=./secrets.nix`.**
> agenix resolves the filename *and* the rules path relative to your
> current directory, not relative to `secrets.nix`. From the repo root,
> `-e david-password.age` quietly creates `./david-password.age` **at the
> repo root** and `--rekey` reports "wasn't created" for every secret.
> `RULES=secrets.nix` without the `./` fails too — Nix needs a real path.

On NixOS hosts `ragenix` is on `PATH`, so you can drop the `nix run …`
prefix. It's a true drop-in for `--rekey`, but it differs in two ways:
it resolves paths relative to the **rules file** rather than your CWD
(which is why `githooks/pre-commit` can run it from the repo root), and
it has no automatic stdin handling — to pipe a value in you must spell
the editor out:

```bash
printf '%s\n' 'the-value' \
  | EDITOR='cp -- /dev/stdin' RULES=./secrets.nix ragenix -e my-secret.age -i ~/.ssh/id_ed25519
```

`cd secrets` + `RULES=./secrets.nix` is correct for both tools, so every
recipe below uses it.

### Add a secret

1. Declare it with the hosts that may decrypt it, in `secrets/secrets.nix`:

   ```nix
   "my-secret.age".publicKeys = allHosts;
   ```

2. Create it by **piping the value in** — no editor involved:

   ```bash
   cd secrets
   printf '%s\n' 'the-secret-value' \
     | RULES=./secrets.nix nix run github:ryantm/agenix -- -e my-secret.age -i ~/.ssh/id_ed25519
   ```

   This works because agenix checks whether stdin is a terminal: when it
   isn't, it ignores `$EDITOR` and does `cp -- /dev/stdin`, so the value
   lands byte-for-byte with exactly one trailing newline.

   For a genuinely multi-line secret an editor is fine — stdin is a tty,
   so `$EDITOR` is honoured — just don't leave a trailing blank line:

   ```bash
   cd secrets
   EDITOR=nano RULES=./secrets.nix \
     nix run github:ryantm/agenix -- -e my-secret.age -i ~/.ssh/id_ed25519
   ```

3. Declare it in `nixos/modules/secrets.nix`, guarded so the flake still
   evaluates on a checkout without it:

   ```nix
   (lib.mkIf (builtins.pathExists ../../secrets/my-secret.age) {
     my-secret.file = ../../secrets/my-secret.age;
   })
   ```

4. Use it as `config.age.secrets.my-secret.path` → `/run/agenix/my-secret`.
   If a non-root process needs to read it, set `owner` and `mode` —
   agenix defaults to `root:root 0400`.

5. Commit **both** `secrets/secrets.nix` and `secrets/my-secret.age`.

### Change your login password

`david`'s password comes from `secrets/david-password.age`, which holds a
**crypt hash** — not a plaintext password.

One command. It prompts for the new password, hashes it, and pipes the
hash straight into the encrypted file — you never see it, never paste it,
and no editor gets a chance to mangle it:

```bash
cd secrets
nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt \
  | RULES=./secrets.nix nix run github:ryantm/agenix -- -e david-password.age -i ~/.ssh/id_ed25519
```

`Files …/david-password.age.before and …/david-password.age differ` is
agenix's **success** message — it's how the tool reports that the content
changed and it re-encrypted. The failure message is the opposite:
`david-password.age wasn't changed, skipping re-encryption`.

> **Don't hand-edit this one.** The file must end with exactly one
> newline. NixOS reads `hashedPasswordFile` and applies a single Perl
> `chomp` (`update-users-groups.pl:243`), which strips one trailing `\n`
> and no more. Leave two — which every editor does by default — and the
> surviving newline is written *into* the `/etc/shadow` password field,
> mangling the record. No password will ever match, and nothing logs an
> error anywhere. The pipe form above avoids this entirely. To check an
> existing secret:
>
> ```bash
> nix shell nixpkgs#age --command age -d -i ~/.ssh/id_ed25519 \
>   secrets/david-password.age | wc -l    # must print 1, not 2
> ```

Then rebuild. **On an impermanent machine that isn't enough:** the live
`/etc/shadow` is restored from `/nix/persist/etc/shadow` on every boot,
so the persisted copy wins over your new secret. Either run `passwd` on
the machine itself (which persists correctly), or delete the frozen copy
and reboot:

```bash
sudo rm /nix/persist/etc/shadow && sudo reboot
```

Two related notes. `root` deliberately keeps `initialPassword = "nixos"`
— NixOS ships root locked, which turns a failed boot into an emergency
shell nobody can log into. And `initialPassword` for `david` is only a
fallback for a checkout where the `.age` file is missing; on a normal
clone the agenix hash always wins.

### Rekey after changing recipients

```bash
cd secrets
RULES=./secrets.nix nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
```

The `githooks/pre-commit` hook does this automatically — but *only* when
`secrets/secrets.nix` is part of the commit. That's deliberate: age
picks a fresh file key on every run, so rekeying on every commit would
rewrite all the ciphertexts and fill history with noise. Enable it once
per clone with `git config core.hooksPath githooks`; it needs `ragenix`
on `PATH` and an identity at `~/.ssh/id_ed25519` (override with
`$AGENIX_IDENTITY`).

### Adding a new machine as a recipient

For a machine that already exists, `cat /etc/ssh/ssh_host_ed25519_key.pub`,
paste it into `secrets.nix`, rekey.

For one you're about to install, you choose between pre-generating the
host key so secrets work on first boot, or harvesting it afterwards —
both paths are written out in
[step 6 of the install runbook](docs/install-bare-metal.md#6-decide-how-the-host-key-is-handled).
For a VM whose key is generated on first boot onto its qcow2:

```bash
ssh-keyscan -p 2222 localhost | grep ed25519    # → paste into secrets.nix, then rekey
```

---

## Running the VMs

```bash
./scripts/run-vm-gui.sh          # nixos-vm, KDE desktop. ctrl+alt+g grabs the keyboard
./scripts/run-vm-headless.sh     # nixos-vm-headless, console only
```

Both scripts build the VM and boot it. SSH is forwarded on **host port
2222** → guest 22, and your Home Manager config directory is shared into
the guest at `/mnt/hmconfig`, which is what makes
`nixos-rebuild --flake /mnt/hmconfig#nixos-vm` work from inside.

On first run the script creates the qcow2 and pre-formats it as ext4
labelled `nixos`. That's necessary because these profiles put `/` on
tmpfs and only `/nix` on disk, so nothing in the boot path would ever
format it.

Two rules about that disk file:

- **To reset a VM, delete its `.qcow2`.** That's the whole procedure.
- **Never add `-snapshot`.** It redirects every write to a temp file
  discarded on exit, which silently breaks persistence — writes to
  `/nix/persist` never reach the image, and you'd spend a while
  wondering why impermanence "isn't working".

### Testing the bare-metal wipe path

`nixos-vm-bare-test` boots the *bare-metal* btrfs rollback inside QEMU,
so you can verify the real wipe mechanism without a real machine.

```bash
./scripts/run-vm-bare-test.sh              # build if needed, then boot
./scripts/run-vm-bare-test.sh --fresh      # delete the image and rebuild
./scripts/run-vm-bare-test.sh --boot-only  # skip the build
```

The verification recipe, using the canary unit baked into the host:

1. First boot (autologin as `david`): `journalctl -u wipe-canary-report`
   should report both canaries absent.
2. Plant them and shut down:

   ```bash
   sudo touch /root-canary
   sudo touch /nix/persist/persist-canary
   touch ~/home-canary
   sudo poweroff
   ```

3. Second boot: the report should say `/root-canary` is gone (so `@` was
   wiped) and `persist-canary` survived. `ls ~/home-canary` should
   **fail** — `/home` is wiped strictly.

### Logging in

`david`, with the password from the agenix secret. `root` / `nixos` at
the console is the escape hatch. The console keymap is **`fr`** (AZERTY),
which is the first thing to suspect when a password you're sure about
gets rejected.

### KVM

Without KVM everything runs 10–20× slower:

```bash
groups | grep -q kvm && echo "KVM enabled" || echo "You need to join the kvm group"
sudo usermod -aG kvm david      # then log out and back in
```

On WSL, see [WSL host setup](docs/wsl-host-setup.md#1-confirm-kvm-is-exposed-to-wsl).

---

## Impermanence in one page

When a profile sets `impermanence = true`, `/` does not survive a
reboot. Everything that matters is declared, and anything undeclared is
transient by construction.

**How the wipe happens** depends on the platform:

- **QEMU VMs** — `/` *is* a tmpfs. There's nothing to wipe; each boot
  starts empty, with only `/nix` on the disk image.
- **Bare metal** — [`nixos/modules/wipe-root.nix`](nixos/modules/wipe-root.nix)
  runs in the stage-1 initrd, before `/` is mounted: it moves the old
  `@` subvolume aside into `@old_roots/<timestamp>` and snapshots a
  pristine `@` from the never-written `@blank`. Old roots are kept for
  **30 days**, which is your recovery window — from a rescue boot,
  `btrfs subvolume snapshot @old_roots/<ts> @` puts one back. This loads
  automatically when `impermanence = true` and `hypervisor = "none"`.

**What survives** is declared in exactly two places, and adding a path
means editing one of them — never writing a new module:

- System paths → `environment.persistence` in
  [`nixos/base.nix`](nixos/base.nix). Machine ID and SSH host keys
  (without them, every boot looks like a brand-new host), NetworkManager
  connections, Bluetooth pairings, `/var/log`, `/var/lib/nixos`.
- User paths → `home.persistence` in
  [`modules/home/persistence.nix`](modules/home/persistence.nix). SSH and
  GPG keys, your `github` and `Documents` directories, shell history
  (fish, atuin, zoxide), direnv approvals, browser profiles, Steam,
  editor state, `.claude`.

**`/etc/shadow` is a special case.** It's copied rather than
bind-mounted, because both NixOS' user-activation script and `passwd`
replace the file via atomic `rename(2)` — which unlinks the inode a bind
mount points at, so writes would never reach `/nix/persist`. Instead: an
activation script restores the persisted copy over the freshly generated
one, and a systemd path unit watching `PathModified` copies it back out
whenever it changes, with a shutdown hook as a safety net. The
consequence to remember is the one in
[Change your login password](#change-your-login-password): the persisted
copy beats a changed secret.

---

## Creating a new profile

1. **Copy the template folder** (never edit it in place):

   ```bash
   cp -r nixos/hosts/_template-bare-metal nixos/hosts/my-laptop
   ```

2. **Copy the template entry** in `nixos/profiles.nix` to a key with
   exactly the same name as the folder — `mkProfile` matches them by
   name:

   ```nix
   my-laptop =
     sharedDesktopProfile
     // {
       hostname = "my-laptop";
       hypervisor = "none";
       impermanence = false;
       extraHomeImports = [gamingHomeImport];
     };
   ```

3. **Edit your copy** of `default.nix`: pick a disk layout (UEFI/btrfs or
   BIOS/ext4), override the disk device if it isn't `/dev/sda`, add any
   hardware quirks. Anything longer than a few lines goes in a file under
   `nixos/hosts/my-laptop/nixos/` and gets imported from there.

4. **Check it evaluates:**

   ```bash
   nix eval ".#nixosConfigurations.my-laptop.config.system.build.toplevel.drvPath"
   ```

   A bare-metal profile will still fail at *build* time with a
   `fileSystems` / `boot.loader` assertion until
   `hardware-configuration.nix` exists. That's expected — it's generated
   during the install.

A QEMU or WSL profile doesn't need a host folder at all; the platform
module supplies the filesystems and bootloader.

---

## Installing a bare-metal machine

The target boots the official NixOS minimal ISO; your workstation pushes
the entire install over SSH with `nixos-anywhere`. **This repartitions
the target disk.**

The happy path, once the profile from
[Creating a new profile](#creating-a-new-profile) exists:

```bash
# On the target, booted from nixos-minimal-*.iso:
ip -4 addr show                 # confirm it has an address
sudo passwd                     # set a root password
sudo sed -i 's/^#*\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# From this repo on your workstation:
nixos-anywhere \
  --flake .#my-laptop \
  --generate-hardware-config nixos-generate-config nixos/hosts/my-laptop/nixos/hardware-configuration.nix \
  root@<target-ip>

# Afterwards — commit what it generated for you:
git add nixos/hosts/my-laptop/nixos/hardware-configuration.nix
git commit -m "Add hardware-configuration for my-laptop"
```

5–15 minutes on a warm `/nix/store`. From then on it's an ordinary
remote: `nixos-rebuild switch --flake .#my-laptop --target-host …`.

**[→ Full runbook: docs/install-bare-metal.md](docs/install-bare-metal.md)**
— disk layouts in detail, TTY networking (Wi-Fi via `iwctl`, USB
tethering), VirtualBox setup, key-based SSH, how the host key and agenix
interact, manual partitioning, baking a custom installer ISO, and a
troubleshooting table.

---

## Adding a module

Decide which evaluator owns it, then decide how widely it applies.

**Which tree:**

- `modules/home/` — user config, packages, dotfiles
- `modules/nixos/` — system services, kernel, desktop suites
- `modules/dual/` — genuinely both halves of one feature, in one module
  that detects its evaluator (see `fish.nix`, `ns/`)
- `nixos/hosts/<name>/{nixos,home}/` — host-specific enough that the
  shared trees shouldn't carry it (fan curves, dual-boot GRUB, hardware
  quirks)

**How to wire it:**

| Scope | Do this |
|---|---|
| Every profile, user side | Add to `imports` in `home.nix` |
| Every profile, system side | Add to `commonNixosModules` in `flake.nix` |
| Every desktop profile | Append to `sharedDesktopProfile.extraNixosImports` in `nixos/profiles.nix` |
| One profile | Set `extraNixosImports` / `extraHomeImports` on that profile |
| One machine, hardware-ish | Drop it in the host folder and import from `default.nix` / `home.nix` |

Careful with per-profile `extraNixosImports`: setting it **replaces** the
list inherited from `sharedDesktopProfile`. Write
`sharedDesktopProfile.extraNixosImports ++ [...]` if you meant to add.

Then validate:

```bash
home-manager switch --flake .#david
sudo nixos-rebuild switch --flake .#nixos-vm
```

---

## Ephemeral shells: `ns`

`ns` gives you three throwaway "worlds" that differ only in how the
filesystem behaves. Packages and run-vs-shell compose on top of any of
them.

| Mode | Flag / sigil | Sees your real files | Writes persist |
|---|---|:---:|:---:|
| live | *(default)* | yes | **yes** |
| isolated | `-i` / `--isolated` / `!` | **no** (empty `/work`) | no |
| rehearse | `-r` / `--rehearse` / `@` | yes | **no** (copy-on-write) |

```bash
ns rg -n foo .        # live: run a tool ephemerally, then it's gone
ns rg fd --           # live: interactive shell with rg + fd on PATH
ns !                  # isolated: empty world, sees nothing real
ns ! URL -N           # isolated: clone a repo, no network
ns @                  # rehearse: your real files, every change reverts on exit
ns @ just deploy      # rehearse: run it for real, then discard everything
ns -h                 # full help
```

Grammar: `ns [MODE] [pkg ...] [ -- | cmd ... ]`. A trailing `--` means
"interactive shell, and the tokens before it are packages"; without it,
the first token is both the command and the package to fetch. `-N`
cuts the network in the sandboxed modes. Rehearse mode needs
unprivileged overlayfs (kernel ≈5.11+); no root, no setuid.

It's a dual module, and it's exported for other flakes as
`homeManagerModules.ns` / `nixosModules.ns` — add this repo as an input
and set `programs.ns.enable = true`. `modules/dual/ns/ns.fish` is also
self-contained enough to drop into any fish config.

Details: [`modules/dual/ns/README.md`](modules/dual/ns/README.md) ·
[`docs/spec-ephemeral-shells.md`](docs/spec-ephemeral-shells.md)

---

## Dev and agent tooling

**Claude Code and Cursor are wired together, deliberately.** Both are
fed from the same pinned upstreams in
[`modules/home/dev/agent-sources.nix`](modules/home/dev/agent-sources.nix)
— one table of `rev` + `hash` for every marketplace, plugin and skill
repo. The project rule is that **nothing lands for one agent alone**:
Cursor has no plugin loader and runs no hooks, so anything Claude gets
from a plugin or a hook has to be re-expressed by hand on the Cursor
side (skills and commands as file trees, MCP servers merged into
`~/.cursor/mcp.json`, hooks as `alwaysApply` rules). The checklist lives
in [`CLAUDE.md`](CLAUDE.md). Both agents share one memory store, via
claude-mem's MCP server.

To bump a pinned upstream: change `rev`, set `hash = lib.fakeHash`,
rebuild, and paste in the hash the error reports.

**`dmux`** is a tmux + git-worktree multiplexer for coding agents. It
isn't in nixpkgs, so it's built here from the npm tarball, with two
patches worth knowing about because they'll need re-checking on every
version bump: one teaches it to bootstrap panes under fish (it types
POSIX `sh` syntax that fish rejects outright, so agents never launch),
and one makes its `client-resized` hook non-blocking (the blocking
version wedges the entire tmux server when you drag a window edge).

**`sesh`** is the session picker behind `ctrl-g` and `prefix+S`, over
live tmux sessions, configured entries and zoxide's frecent
directories. `ctrl-x` in the picker kills the highlighted session.

**`dbhub`** exposes every Sencrop database to the agents as one MCP
server, with one tool per database rather than a generic
"execute_sql" — so the database name is part of the tool name and preprod
can't be mistaken for prod. Credentials live in
`~/.config/dbhub/dbhub.toml`, deliberately unmanaged and hand-created at
mode `0600`, because anything Nix writes lands world-readable in
`/nix/store`.

**Cachix** is set up at the system level, with the auth token injected
per-invocation from an agenix secret by a fish wrapper — never exported
into the environment, so a push credential doesn't leak into every child
process. **Tailscale** authenticates from an agenix key file, so a fresh
machine joins the tailnet on first boot.

---

## Documentation index

| Document | What's in it |
|---|---|
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The architecture in depth: the four principles, where a given thing belongs, how `mkProfile` works, invariants not to break |
| [`docs/install-bare-metal.md`](docs/install-bare-metal.md) | Full install runbook: ISO, networking, disko layouts, host keys, `nixos-anywhere`, troubleshooting |
| [`docs/wsl-host-setup.md`](docs/wsl-host-setup.md) | One-time Windows-side setup: KVM, AV exclusions, `.wslconfig`, `/nix` on real ext4 |
| [`docs/spec-ephemeral-shells.md`](docs/spec-ephemeral-shells.md) | The `ns` spec (approved, implemented) |
| [`docs/spec-agent-multiplexer.md`](docs/spec-agent-multiplexer.md) | The `wt` spec (draft, not implemented) |
| [`modules/dual/ns/README.md`](modules/dual/ns/README.md) | `ns` reference, including standalone use outside Nix |
| [`CLAUDE.md`](CLAUDE.md) | Conventions for AI agents working in this repo — including the parity rule |
| [`secrets/secrets.nix`](secrets/secrets.nix) | Recipient list, with the agenix workflows in its header comments |
| [`pins.nix`](pins.nix) | Every version pin and the reason for it |
