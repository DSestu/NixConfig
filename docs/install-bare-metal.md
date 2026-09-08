# Installing a machine from scratch

This is the long-form runbook for putting one of this flake's profiles
onto a real machine — bare metal, a fresh VirtualBox VM, a cloud
instance, anything you can boot from an ISO and SSH into.

The shape of it: **the target boots the official NixOS minimal ISO, and
your workstation pushes the whole install over SSH with
[`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere).**
No OVA, no image-build pipeline, no `cptofs`.

> **This is destructive.** `nixos-anywhere` repartitions the target disk.
> There is no confirmation prompt.

`nixos-anywhere` ships with Home Manager here
(`modules/home/deployment.nix`). If `which nixos-anywhere` comes back
empty, run `home-manager switch --flake .#david` first.

For the short version — the happy path in five commands — see
[Installing a bare-metal machine](../readme.md#installing-a-bare-metal-machine)
in the README.

## Contents

- [1. Create the profile](#1-create-the-profile)
- [2. Choose a disk layout](#2-choose-a-disk-layout)
- [3. Boot the target from the minimal ISO](#3-boot-the-target-from-the-minimal-iso)
- [4. Get the target on the network](#4-get-the-target-on-the-network)
- [5. Enable SSH on the target](#5-enable-ssh-on-the-target)
- [6. Decide how the host key is handled](#6-decide-how-the-host-key-is-handled)
- [7. Run `nixos-anywhere`](#7-run-nixos-anywhere)
- [8. After the install](#8-after-the-install)
- [Appendix A — manual partitioning](#appendix-a--manual-partitioning)
- [Appendix B — generating `hardware-configuration.nix` by hand](#appendix-b--generating-hardware-configurationnix-by-hand)
- [Appendix C — bake a custom installer ISO](#appendix-c--bake-a-custom-installer-iso)
- [Troubleshooting](#troubleshooting)

---

## 1. Create the profile

Never install `_template-bare-metal` itself — the leading underscore
means "skeleton, don't deploy". Copy it.

```bash
cp -r nixos/hosts/_template-bare-metal nixos/hosts/my-laptop
```

Then copy the `_template-bare-metal` block in **`nixos/profiles.nix`**
to a new key with exactly the same name as your folder:

```nix
my-laptop =
  sharedDesktopProfile
  // {
    hostname = "my-laptop";
    hypervisor = "none";
    impermanence = false;          # see step 2 before flipping this on
    extraHomeImports = [gamingHomeImport];
  };
```

The folder name and the profile key **must match** — `mkProfile`
discovers `nixos/hosts/<key>/default.nix` by name.

Leave the template files themselves untouched so they stay a clean
reference. Everything you customize goes in your copy.

## 2. Choose a disk layout

Partitioning is declarative. `disko.nixosModules.default` is already in
every profile's module list, but it stays completely inert until a host
folder imports a layout — that's the opt-in. Your copied `default.nix`
already imports the UEFI one; comment-swap the line to switch.

| Layout | Firmware | Root filesystem | Bootloader | Works with `impermanence = true`? |
|---|---|---|---|---|
| `nixos/disko/single-disk-uefi.nix` | UEFI | **btrfs**, label `nixos`, five subvolumes | systemd-boot | **Yes** — this is the one wipe-root expects |
| `nixos/disko/single-disk-bios.nix` | Legacy BIOS | flat ext4, `/boot` on the root FS | GRUB on `/dev/sda` | **No** — flat ext4 has no `@blank` to roll back from |

Use the UEFI layout for modern bare metal, VirtualBox VMs created with
"Enable EFI" ticked, and most cloud images. Use the BIOS layout for
VirtualBox VMs created *without* "Enable EFI" (that's the default) and
for older firmware.

### What the UEFI layout actually builds

- A separate 512 MiB FAT32 ESP at `/boot` (`umask=0077`). It lives
  *outside* the btrfs filesystem, so the bootloader is untouched by
  subvolume rollbacks.
- All remaining space as one btrfs filesystem labelled `nixos` —
  `wipe-root.nix` finds it via `/dev/disk/by-label/nixos` — carrying:

  | Subvolume | Mounted at | Survives a wipe? |
  |---|---|---|
  | `@` | `/` | **No** — rolled back from `@blank` every boot |
  | `@blank` | *(never mounted)* | Immutable rollback source, kept read-only by an activation script |
  | `@nix` | `/nix` | Yes — the store must survive or the system won't reboot |
  | `@persist` | `/nix/persist` | Yes — impermanence's bind-mount source |
  | `@log` | `/var/log` | Yes — journals survive without polluting `@persist` |

  All four mounted subvolumes use `compress=zstd,noatime`, and
  `/nix/persist` is marked `neededForBoot` so it exists in stage 1.

See [Impermanence](../readme.md#impermanence-in-one-page) for how the
wipe itself works.

### If the disk isn't `/dev/sda`

Uncomment and edit the override in your host folder's `default.nix`:

```nix
disko.devices.disk.main.device = lib.mkForce "/dev/nvme0n1";
```

Common values: NVMe `/dev/nvme0n1`, second SATA `/dev/sdb`,
virtio/cloud `/dev/vda`.

### The `hardware-configuration.nix` guard

Your copied `default.nix` wraps that import in `builtins.pathExists`, so
the flake evaluates fine before the file exists. Bare-metal profiles
will still fail at *build* time with a `fileSystems` / `boot.loader`
assertion — that's the expected signal that you haven't installed yet,
not a bug. Step 7 generates the file; the guard flips; subsequent
rebuilds import it.

## 3. Boot the target from the minimal ISO

Grab `nixos-minimal-*-x86_64-linux.iso` from
<https://nixos.org/download/>, or build one with
`nix build nixpkgs#nixos-minimal`.

- **Bare metal** — write it to a USB stick and boot from it:

  ```bash
  dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
  ```

- **Fresh VirtualBox VM** — New → Linux / Other Linux 64-bit, ≥ 30 GB
  disk, 4–8 GB RAM, attach the ISO as the optical drive. In *Settings →
  Network → Adapter 1*, set *Attached to* → **Bridged Adapter** so WSL
  can reach the VM on a LAN IP.

  Bridged unavailable? Use NAT plus a port-forward `Host 2222 → Guest
  22`, then SSH to `root@<windows-host-lan-ip>:2222` — **not**
  `127.0.0.1`, because WSL2 sits behind its own NAT. Mirrored networking
  (see [WSL host setup, step 5](wsl-host-setup.md#5-configure-wsl2-resources-and-networking))
  is what makes the bridged path work.

- **Cloud VM** — most providers offer a NixOS minimal image directly.
  Skip to step 4.

## 4. Get the target on the network

The minimal ISO is a bare TTY: no GUI applet, no NetworkManager. Check
what's already up:

```bash
ip -4 addr show
ping -c 3 1.1.1.1
```

If you see an `inet` on `enp…`/`eth…`/`wlan…` and ping works, skip to
step 5.

**Wired Ethernet** — DHCP is automatic. If nothing shows up:

```bash
sudo systemctl restart systemd-networkd
```

**Wi-Fi** — the ISO ships `iwd`:

```bash
iwctl
[iwd]# device list                     # note the station, e.g. wlan0
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect "<SSID>"  # prompts for the passphrase
[iwd]# exit
```

Re-check `ip -4 addr show` for the new address.

**USB tethering off your phone** — genuinely the easiest option. Plug in
a cable, enable USB tethering; a `usb0` / `enp…u…` interface appears and
DHCPs immediately. Same for wired tethering on iPhones. No config at
all.

**Ping by IP works but names don't resolve** — drop in a resolver:

```bash
echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
```

## 5. Enable SSH on the target

The installer's `nixos` user has no password, and root-over-SSH with a
password is off by default. Pick one:

**Option A — password auth.** Quickest, fine for a one-shot install:

```bash
sudo passwd                                                            # set a root password
sudo sed -i 's/^#*\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

Sanity-check from your workstation: `ssh root@<target-ip>`, log in,
`exit`.

**Option B — public key.** Preferred, because `nixos-anywhere` won't
stop for password prompts mid-run. On the target:

```bash
sudo passwd nixos
sudo systemctl start sshd
```

Then from your workstation:

```fish
ssh-copy-id nixos@<target-ip>            # uses the password you just set
ssh-copy-id root@<target-ip>             # nixos-anywhere connects as root by default
```

After that, `ssh root@<target-ip>` should drop straight into a shell.

If you do this often, [Appendix C](#appendix-c--bake-a-custom-installer-iso)
bakes sshd and your key into a custom ISO and makes this whole step
disappear.

## 6. Decide how the host key is handled

Every agenix secret is encrypted *to a list of recipients*, and a NixOS
host decrypts its secrets with its **SSH host key**. A brand-new machine
has no host key yet, so you have to choose when it gets one.

**Option A — pre-generate the key before installing.** The new host can
decrypt secrets on its very first boot. Do this if the profile needs
`david-password.age` or `tailscale-auth-key.age` to work immediately.

```bash
ssh-keygen -t ed25519 -N "" -f /tmp/newhost-ssh-host-key
cat /tmp/newhost-ssh-host-key.pub          # → paste into secrets/secrets.nix

# Re-encrypt every secret for the new recipient list. Run this from the
# secrets/ directory — agenix resolves paths relative to your CWD, and
# from the repo root it reports "wasn't created" for every secret.
cd secrets
RULES=./secrets.nix nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
cd ..

# Stage the key for nixos-anywhere to inject:
mkdir -p /tmp/newhost-extra-files/etc/ssh
cp /tmp/newhost-ssh-host-key     /tmp/newhost-extra-files/etc/ssh/ssh_host_ed25519_key
cp /tmp/newhost-ssh-host-key.pub /tmp/newhost-extra-files/etc/ssh/ssh_host_ed25519_key.pub
chmod 600 /tmp/newhost-extra-files/etc/ssh/ssh_host_ed25519_key
```

Then add `--extra-files /tmp/newhost-extra-files` to the command in step
7, and clean up afterwards:

```bash
rm -rf /tmp/newhost-ssh-host-key /tmp/newhost-ssh-host-key.pub /tmp/newhost-extra-files
```

**Option B — harvest the key after first boot.** Simpler; the machine
just can't read secrets until you've done it. Install first, then:

```bash
ssh-keyscan <target-ip> | grep ed25519     # → paste into secrets/secrets.nix
cd secrets
RULES=./secrets.nix nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
```

…and rebuild the host so it picks up the re-encrypted secrets. With no
usable host key, `david`'s password falls back to `initialPassword`
(`nixos`) only if `secrets/david-password.age` is *absent* from the
checkout — it isn't, so on a normal clone the account simply has no
working password until the rekey lands. Plan accordingly: either use
Option A, or make sure you have console access.

See [Secrets](../readme.md#secrets-agenix) for the rest of the agenix
workflow.

## 7. Run `nixos-anywhere`

With disko (the declarative path from step 2):

```fish
nixos-anywhere \
  --flake .#my-laptop \
  --generate-hardware-config nixos-generate-config nixos/hosts/my-laptop/nixos/hardware-configuration.nix \
  root@<target-ip>
```

Without disko (the manual path from [Appendix A](#appendix-a--manual-partitioning)):

```fish
nixos-anywhere \
  --flake .#my-laptop \
  --no-disko \
  --phases install,reboot \
  --generate-hardware-config nixos-generate-config nixos/hosts/my-laptop/nixos/hardware-configuration.nix \
  root@<target-ip>
```

`--generate-hardware-config nixos-generate-config <path>` SSHes into the
target, runs `nixos-generate-config` there, and writes the result back
into your checkout — so the closure it builds has the right kernel
modules, microcode and root-FS identifiers baked in.

What happens, in order:

1. The system closure is built **locally**.
2. It's streamed to the target over SSH.
3. `nixos-install` runs against the disko (or pre-mounted) layout.
4. The target reboots as your profile.

Wall time on a warm `/nix/store`: **5–15 minutes**.

## 8. After the install

The target is now an ordinary NixOS host running your profile.

1. Log in as `david`. The password comes from the agenix secret
   `secrets/david-password.age`, decrypted with the host key from step 6.
   Change it with `passwd`. Note the console keymap is **`fr`** (AZERTY)
   — worth remembering before you conclude the password is wrong.

2. Commit the generated hardware config:

   ```fish
   git add nixos/hosts/my-laptop/nixos/hardware-configuration.nix
   git commit -m "Add hardware-configuration for my-laptop"
   ```

   Drop `--generate-hardware-config` from any future `nixos-anywhere`
   run — the committed file is the source of truth from here on.

3. Push updates like any other remote:

   ```fish
   sudo nixos-rebuild switch --flake .#my-laptop \
     --target-host david@<target-ip> --use-remote-sudo
   ```

   Dry-run it first with `nixos-rebuild build` and the same flags.

4. If you want impermanence on this host, flip `impermanence = true` in
   `nixos/profiles.nix` **only** if you used the UEFI/btrfs layout. Then
   rebuild and reboot, and verify the wipe actually behaves — you can
   rehearse the exact mechanism locally first with
   `./scripts/run-vm-bare-test.sh`, which boots the bare-metal wipe path
   inside QEMU and reports canary state to the journal.

---

## Appendix A — manual partitioning

You can skip disko entirely and partition by hand. On the target, before
running `nixos-anywhere` with `--no-disko`:

```bash
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 513MiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary 513MiB 100%
mkfs.fat -F32 -L boot /dev/sda1
mkfs.ext4 -L nixos /dev/sda2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
```

This gives you a flat ext4 root, so **don't** pair it with
`impermanence = true`.

## Appendix B — generating `hardware-configuration.nix` by hand

`--generate-hardware-config` covers this automatically. If you need to
do it yourself — an already-running machine you didn't install with
`nixos-anywhere`, say:

```bash
# During an install, with the target root mounted at /mnt:
sudo nixos-generate-config --root /mnt --show-hardware-config

# On a running system:
sudo nixos-generate-config --show-hardware-config
```

Pipe it straight into the host folder from your workstation:

```bash
ssh <user>@<remote> 'sudo nixos-generate-config --show-hardware-config' \
  > nixos/hosts/my-laptop/nixos/hardware-configuration.nix
git add nixos/hosts/my-laptop/nixos/hardware-configuration.nix
git commit -m "Add hardware-configuration.nix for my-laptop"
```

Add `--no-filesystems` when the host uses disko, so the generated file
doesn't fight disko over `fileSystems` — disko stays the single source
of truth for the disk layout.

Validate without touching the machine:

```bash
nix eval ".#nixosConfigurations.my-laptop.config.system.build.toplevel.drvPath"
```

## Appendix C — bake a custom installer ISO

Worth it if you do this regularly: an ISO with sshd already on, your key
already trusted, and optionally Wi-Fi credentials pre-loaded. Booting it
*is* steps 4 and 5.

Create `nixos/installer-iso.nix`:

```nix
{modulesPath, ...}: {
  imports = [(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")];

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAA... david@wsl"   # your workstation public key
  ];

  # Optional: auto-connect to Wi-Fi on boot.
  networking.wireless.enable = true;
  networking.wireless.networks."<SSID>".psk = "<passphrase>";
}
```

Wire it as a flake output next to `nixosConfigurations`:

```nix
nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [./nixos/installer-iso.nix];
};
```

Build it:

```fish
nix build .#nixosConfigurations.installer.config.system.build.isoImage
ls result/iso/                       # nixos-*.iso
```

Write it to USB (`dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M
status=progress`) or attach it in VirtualBox. After boot the target has
an IP, sshd running and your key trusted — go straight to step 7.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `nixos-anywhere` errors about missing `disko.devices` | No layout imported. Finish [step 2](#2-choose-a-disk-layout), or partition by hand and pass `--no-disko --phases install,reboot`. |
| No IP on the target | [Step 4](#4-get-the-target-on-the-network) wasn't applied. Wired: `sudo systemctl restart systemd-networkd` and check the cable. Wi-Fi: `iwctl` → `station wlan0 connect "<SSID>"`. Fastest fallback: USB-tether a phone. |
| `ping 1.1.1.1` works, `ping nixos.org` fails | DNS. `echo 'nameserver 1.1.1.1' \| sudo tee /etc/resolv.conf` |
| `Permission denied (publickey,password)` | `sudo passwd` wasn't run on the target, sshd isn't started, or `PermitRootLogin` is still `prohibit-password`. Redo [step 5](#5-enable-ssh-on-the-target) — Option A flips the sshd_config line for you. |
| `Failed to find an installation root` | Manual-partition path: you forgot `mount /dev/disk/by-label/nixos /mnt` (and `/mnt/boot`). |
| First boot stops in stage 1 / "no init found" | Bootloader doesn't match the firmware. UEFI target → the UEFI layout (systemd-boot). BIOS VM → the BIOS layout (`boot.loader.grub.device = "/dev/sda"`). Fix the host module and re-run. |
| `hardware-configuration.nix` regenerates on every install | Drop `--generate-hardware-config` after the first run and commit the file. |
| Login rejected after a successful install | Either the host key isn't a recipient yet ([step 6](#6-decide-how-the-host-key-is-handled)) or you're typing a QWERTY password on an AZERTY console (`console.keyMap = "fr"`). |
| Wipe ate something you needed | Add the path to `environment.persistence` in `nixos/base.nix` (system) or `home.persistence` in `modules/home/persistence.nix` (user). Recover the previous root from `@old_roots/<timestamp>` within 30 days — see [Impermanence](../readme.md#impermanence-in-one-page). |
| WSL can't reach the target's IP | With VirtualBox + bridged, the Windows host and the VM must share a LAN, and WSL needs `networkingMode=mirrored` ([WSL setup step 5](wsl-host-setup.md#5-configure-wsl2-resources-and-networking)). Without mirrored networking, use NAT + a port-forward to the *Windows host's* LAN IP. |
