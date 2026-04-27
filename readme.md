# Home Manager + NixOS Flake

## Daily commands

### Update packages

```bash
nix flake update nixpkgs
```

### Garbage collect

```bash
nix-collect-garbage -d
```

### Repair Nix store

Use after a build is killed mid-write or if a build fails with
`Invalid argument` / `path is missing` errors — the WSL `ext4.vhdx` can
take damage from abrupt shutdowns and corrupt store paths. This
verifies every path's contents against its hash and re-fetches anything
broken.

```bash
sudo nix-store --verify --check-contents --repair
```

Targeted variant if you already know the bad path:

```bash
sudo nix-store --delete --ignore-liveness /nix/store/<hash>-<name>
```

Nix re-realises the path on the next build.

### Export plasma settings

```bash
nix run github:nix-community/plasma-manager
```

### Refresh AppImage hash

Compute latest SRI hash:

```bash
./scripts/update-appimage-hash.sh "https://example.com/MyApp-x86_64.AppImage"
```

Compute and replace an existing hash in a file:

```bash
./scripts/update-appimage-hash.sh "https://example.com/MyApp-x86_64.AppImage" --replace modules/home/gaming.nix "sha256-OLD_HASH"
```

## WSL host setup (run once)

If you build from WSL on Windows, do this setup before the first build.
Skipping it produces a pathological failure mode: `cptofs` (the tool
that copies the Nix closure into the raw OVA disk image) pegs one CPU
at 99% for hours instead of finishing in minutes, because Windows
antivirus is scanning every write into the WSL `ext4.vhdx`.

### 1. Confirm KVM is exposed to WSL

Inside WSL:

```bash
ls -la /dev/kvm
```

Expect a character device with `crw-rw-rw-` permissions. If it's
missing, enable nested virtualization on the Windows side (PowerShell
as Administrator):

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --update
wsl --shutdown
```

Reboot if BIOS Intel VT-x / AMD-V is disabled.

### 2. Locate every WSL distro's `ext4.vhdx`

`wsl --import`-style distros (NixOS-WSL most commonly) live wherever
you placed them at import time, not under `AppData\Local\Packages`.
List them all:

```powershell
Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss |
  ForEach-Object { Get-ItemProperty $_.PSPath } |
  Select-Object DistributionName, BasePath
```

Note every `BasePath` — there's an `ext4.vhdx` inside each. Also catch
the Microsoft Store distros:

```powershell
(Get-ChildItem $env:USERPROFILE\AppData\Local\Packages -Filter ext4.vhdx -Recurse).FullName
```

Keep the full list of paths handy for the next two steps.

### 3. Exclude WSL from Windows Defender

PowerShell as Administrator. Repeat the first `Add-MpPreference` line
once per `BasePath` from step 2:

```powershell
# Per-distro VHDX paths — highest impact:
Add-MpPreference -ExclusionPath "C:\Path\To\Distro\ext4.vhdx"
# ...one line per distro.

# Catch-all for Store-installed distros and live filesystem views:
Add-MpPreference -ExclusionPath "$env:USERPROFILE\AppData\Local\Packages"
Add-MpPreference -ExclusionPath "\\wsl$"
Add-MpPreference -ExclusionPath "\\wsl.localhost"

# Process exclusions:
Add-MpPreference -ExclusionProcess "wsl.exe"
Add-MpPreference -ExclusionProcess "wslservice.exe"
Add-MpPreference -ExclusionProcess "wslhost.exe"
Add-MpPreference -ExclusionProcess "vmwp.exe"
Add-MpPreference -ExclusionProcess "vmcompute.exe"
```

Verify:

```powershell
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess
```

### 4. Exclude WSL from any third-party antivirus

Defender exclusions do nothing for third-party AV (Avast, AVG, Norton,
McAfee, Kaspersky, etc.). Add the same paths to whichever you have
installed. For Avast specifically: Menu → Settings → General →
Exceptions → add each `ext4.vhdx`, the `BasePath` parent dirs, and
`\\wsl$`.

Sanity check: pause AV shields for 10 minutes and run a build. If it
suddenly flies, that AV is missing exclusions.

### 5. Configure WSL2 resources and networking

Create `C:\Users\<you>\.wslconfig` on the Windows side:

```ini
[wsl2]
memory=24GB
processors=12
swap=8GB
networkingMode=mirrored
```

Tune memory/processors to leave Windows ~8 GB and a couple of cores.
`networkingMode=mirrored` requires WSL ≥ 2.0.0 (`wsl --version` to
check). It avoids substituter hangs caused by WSL's default NAT.

Apply:

```powershell
wsl --shutdown
```

Reopen the WSL shell. Inside WSL, verify:

```bash
nproc
free -h
```

### 6. Confirm `/nix` is on real ext4

Inside WSL:

```bash
df -h /nix/store
mount | grep '/nix'
```

The `Filesystem` column must be a real block device (`/dev/sdX`), not
`drvfs` or a Windows path. If `/nix` is on a Windows path you'll pay
10–100× penalties on every store operation; move the distro or
reinstall it inside the Linux filesystem before going further.

### 7. Build the OVA

```bash
./scripts/build-vbox-ova.sh
```

Or, with live logs and a fast bail-out on stalled downloads (recommended
for first build, when most cache misses happen):

```bash
nix build .#nixosConfigurations.nixos-vbox.config.system.build.virtualBoxOVA \
  -L \
  --max-jobs auto \
  --cores 0 \
  --option connect-timeout 10 \
  --option stalled-download-timeout 30
```

While the build runs, in another shell:

```bash
ps -eo pid,etime,cmd | grep -E 'cptofs|qemu|cc1' | grep -v grep
free -h
```

`cptofs` should appear once, push through the closure in 5–15 minutes,
and the whole build should finish well under an hour even on a fresh
`/nix`. If `cptofs` sits at 99% CPU for more than ~20 minutes, an AV
exclusion is still missing — go back to step 3 or 4.

### Troubleshooting cheat sheet

- **`cptofs` at 99% CPU for hours** → AV scanning the `ext4.vhdx`.
  Confirm with `ps -eo pid,etime,cmd | grep cptofs`. Re-check steps 3–4
  including any third-party AV.
- **Build meter `[X/Y/Z built]` frozen, no active builders in `ps`** →
  stalled substituter connection. Ctrl-C, kill leftovers
  (`sudo pkill -9 -f 'nix build'; sudo pkill -9 -f qemu`), retry with
  `--option connect-timeout 10 --option stalled-download-timeout 30`.
  `networkingMode=mirrored` in `.wslconfig` prevents most recurrences.
- **Hundreds of derivations rebuilding that "should" be cached** → you
  bumped `nixpkgs` to a commit Hydra hasn't finished serving. Either
  wait a few hours or pin `flake.lock` back to a known-good commit
  (`git checkout HEAD~1 -- flake.lock`).
- **`/dev/kvm` missing** → step 1 wasn't applied or BIOS virtualization
  is off. Without KVM, anything that spawns a nested VM (some image
  builders, `nixos-rebuild build-vm`) falls back to TCG and runs
  20–50× slower.
- **Same closure downloaded twice** → you're hopping between WSL
  distros. Each distro has its own `/nix/store`. Pick one for builds
  and stick to it.

## VM workflows

VM targets reuse the same base machine configuration as real-machine targets; only hypervisor-specific modules differ.

### QEMU GUI

Grab keyboard with `ctrl + alt + g`.

```bash
./scripts/run-vm-gui.sh
```

### QEMU headless

```bash
./scripts/run-vm-headless.sh
```

### VirtualBox image (OVA)

```bash
./scripts/build-vbox-ova.sh
```

Import the generated `*.ova` from `./result/` into VirtualBox, then start it from the VirtualBox UI.

The `nixos-vbox` profile has `impermanence = true`. On every boot, an
initrd `wipe-root` service blows away `/` except for `/nix`, `/boot`, and
`/tmp`; everything declared under `environment.persistence."/nix/persist"`
(see `nixos/base.nix`) and `home.persistence."/nix/persist"` (see
`modules/home/persistence.nix`) is bind-mounted back from `/nix/persist`.
If you want a path to survive reboots, add it to one of those lists.

First boot specifics:

- `users.users.david.initialPassword = "nixos"` seeds the password. After
  first boot, `/etc/shadow` is persisted, so `passwd` changes stick.
- Host SSH keys are generated on first boot and then persisted.
- Anything you put in your home directory but didn't list in
  `modules/home/persistence.nix` will be gone after the next reboot —
  that is the point. Add it to the list and rebuild if you want it to
  stay.

### Importing and configuring the VM in VirtualBox

Tutorial for the first import. Run these on the **Windows host** (not in
WSL) — VirtualBox is a Windows app and only sees Windows paths.

#### 1. Locate the OVA from Windows

`./scripts/build-vbox-ova.sh` produces a file under `./result/` inside
WSL. Windows reaches it through `\\wsl$\<distro-name>\…`. With this repo
at `D:\projets_python_ssd\Sencrop\NixConfig` (a Windows path that's also
mounted into WSL), the OVA is just at:

```text
D:\projets_python_ssd\Sencrop\NixConfig\result\nixos-<version>.ova
```

If the repo lives inside the WSL Linux filesystem instead, the path
looks like:

```text
\\wsl$\NixOS\home\david\NixConfig\result\nixos-<version>.ova
```

(`result/` is a symlink to a path under `/nix/store`. Both Windows and
the Import dialog follow it transparently.)

#### 2. Import the appliance

VirtualBox UI → **File → Import Appliance** → select the `.ova` from
step 1 → **Next**. On the appliance settings page, before clicking
**Finish**, edit:

- **Name** — set to `nixos-vbox` (matches the shared-folder commands
  below).
- **CPU** — 4 to 6 cores.
- **RAM** — 8192 MB minimum if you'll run KDE; 4096 MB for headless.
- **MAC address policy** — *Generate new MAC addresses for all network
  adapters*.
- **Machine Base Folder** — anywhere with ≥ 30 GB free. The VM disk
  will live next to the `.vbox` file here.

Click **Finish**. Import takes 1–3 minutes (it's just unpacking the OVA
into a `.vdi` plus a `.vbox` definition).

#### 3. Adjust VM settings before first boot

Right-click the new VM → **Settings**:

- **System → Processor** → enable *Nested VT-x/AMD-V* if you plan to
  run nested VMs inside the guest.
- **Display → Screen** → Video Memory: **128 MB**; Graphics Controller:
  **VMSVGA**; tick *Enable 3D Acceleration* (KDE Plasma's compositor
  uses it).
- **Network → Adapter 1** → set *Attached to* to **Bridged Adapter**,
  pick your physical NIC. This gives the VM a LAN IP that WSL can reach
  for remote `nixos-rebuild` later. If bridged isn't an option (some
  Wi-Fi drivers refuse), use NAT and add a port forward for SSH:
  *Advanced → Port Forwarding* → add `Host 2222 → Guest 22`.
- **Shared Folders** → add a folder pointing at the repo (see
  *VirtualBox shared folder* below) if you want to edit the flake from
  Windows and rebuild inside the guest. Optional.
- **USB** → leave on USB 1.1 unless you've installed the VirtualBox
  Extension Pack on Windows.

Click **OK**.

#### 4. First boot

Start the VM. Expect:

1. GRUB menu (~5 s) → kernel boot (~10 s).
2. systemd brings up SDDM and auto-logs in as `david`. KDE Plasma
   appears. The `wipe-root` impermanence service ran during initrd, so
   `/etc/shadow`, host SSH keys, etc. are being created fresh and saved
   to `/nix/persist` on this first boot.
3. If you want to log in manually instead of auto-login: user `david`,
   password `nixos`.

#### 5. Change the password (and prove impermanence works)

Open Konsole and run:

```bash
passwd                  # change from "nixos" to something real
sudo reboot
```

Log back in with the new password. If it works, persistence of
`/etc/shadow` is wired correctly. If you're back to `nixos` after the
reboot, persistence is broken — re-check `environment.persistence` in
`nixos/base.nix`.

Bonus check: before rebooting, `touch /tmp-test-file` and
`touch ~/throwaway`. After reboot, `/tmp-test-file` is gone (root was
wiped) and `~/throwaway` is gone (home isn't in
`modules/home/persistence.nix`). That's impermanence doing its job.

#### 6. Get the VM's IP for remote rebuilds

Inside the guest:

```bash
ip -4 addr show | awk '/inet / && $2 !~ /127\.0\.0\.1/ { print $2 }'
```

Note the IP. From WSL, future config changes don't need a new OVA — you
push the rebuild straight in:

```bash
sudo nixos-rebuild switch --flake .#nixos-vbox \
  --target-host david@<vm-ip> --use-remote-sudo
```

(With NAT + port-forward instead of bridged: `david@127.0.0.1:2222`
from inside WSL won't work — WSL2 has its own NAT. Use the Windows
host IP from WSL: `david@<windows-host-lan-ip>:2222`.)

#### 7. Optional: install Guest Additions

The flake already enables the in-guest service
(`virtualisation.virtualbox.guest.enable = true;`) so clipboard sharing,
auto-resize, and `vboxsf` shared folders work without manually mounting
the Guest Additions ISO.

#### 8. Snapshot

Right-click the VM → **Snapshots → Take**. Call it `clean-first-boot`.
If you ever want a known-good rollback target, this is it. Re-snapshot
after any config change you want to preserve as a baseline.

#### Troubleshooting

- **VM hangs at GRUB or kernel panics on first boot** → the OVA was
  built without UEFI but the VM was set to EFI (or vice-versa). In VM
  Settings → System → Motherboard, match what `virtualbox-image.nix`
  produced (BIOS by default).
- **Black screen after SDDM** → 3D acceleration mismatch. Toggle it in
  Display → Screen and reboot.
- **Bridged adapter dropdown is empty** → VirtualBox NDIS6 driver isn't
  installed on the host NIC. Reinstall VirtualBox or fall back to NAT
  with port forwarding.
- **`nixos-rebuild --target-host` fails with `Permission denied`** →
  the `david` user has `extraGroups = ["wheel"]` but `--use-remote-sudo`
  needs a working password or SSH key on the remote `sudo`. Either set
  a password (`passwd` inside the VM) or add your WSL SSH key to
  `users.users.david.openssh.authorizedKeys.keys` in `base.nix` and
  rebuild.
- **`passwd` change doesn't survive reboot** → `/etc/shadow` not in the
  persisted files list, or the wipe-root service is wiping after the
  bind mount. Check `nixos/base.nix` against the version that lists
  `/etc/shadow` under `files = […]`.

### VirtualBox shared folder (repo on host)

Add the repo as a shared folder from the host (Windows PowerShell/CMD):

```bash
VBoxManage sharedfolder add "nixos-vbox" --name "nixconfig" --hostpath "D:\projets_python_ssd\Sencrop\NixConfig" --automount
```

Inside the NixOS guest:

```bash
sudo mkdir -p /mnt/nixconfig
sudo mount -t vboxsf -o uid=$(id -u),gid=$(id -g),dmode=775,fmode=664 nixconfig /mnt/nixconfig
ls /mnt/nixconfig
```

If your user cannot access the mount:

```bash
sudo usermod -aG vboxsf $USER
```

Then log out/in (or reboot).

Optional: make the mount persistent for the `nixos-vbox` profile by adding this to
`nixos/hosts/nixos-vbox/default.nix`:

```nix
fileSystems."/mnt/nixconfig" = {
  device = "nixconfig";
  fsType = "vboxsf";
  options = [ "rw" "uid=1000" "gid=100" "dmode=0775" "fmode=0664" ];
};
```

If unmount fails with "target is busy", leave the folder and use lazy unmount:

```bash
cd ~
sudo umount -l /mnt/nixconfig
sudo mount -t vboxsf -o uid=$(id -u),gid=$(id -g),dmode=775,fmode=664 nixconfig /mnt/nixconfig
```

If `lsof` is available, you can inspect active users before unmounting:

```bash
sudo lsof +D /mnt/nixconfig
```

### Rebuild inside VM

```bash
nixos-rebuild build --flake .#nixos-vbox
sudo ./result/bin/switch-to-configuration switch
```

## Remote deployment

### Local -> remote update (`nixos-rebuild`)

Run from this repo on your local machine:

```bash
sudo nixos-rebuild switch --flake .#<profile-name> --target-host <user>@<remote-host> --use-remote-sudo
```

Example:

```bash
sudo nixos-rebuild switch --flake .#nixos-vm --target-host david@192.168.1.50 --use-remote-sudo
```

Optional pre-check build:

```bash
sudo nixos-rebuild build --flake .#<profile-name> --target-host <user>@<remote-host> --use-remote-sudo
```

### Remote install/reprovision (`nixos-anywhere`)

Use this for a clean first install (or full reprovision) of any flake
profile onto a remote machine — bare metal, a fresh VirtualBox VM, a
cloud VM, anything you can boot from an ISO and SSH into. The target
boots the official NixOS minimal ISO, your local machine pushes the
install over SSH. No OVA, no `cptofs`, no image-build pipeline involved.

**WARNING:** destructive — `nixos-anywhere` repartitions the target disk.

`nixos-anywhere` is already in home-manager via
`modules/home/deployment.nix`. If `which nixos-anywhere` returns
nothing, run `home-manager switch --flake .#david` first.

#### 1. Get the NixOS minimal ISO onto the target

Download `nixos-minimal-*-x86_64-linux.iso` from
<https://nixos.org/download/> (or build one with
`nix build nixpkgs#nixos-minimal`). Boot the target from it:

- **Bare metal**: `dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress`
  to a USB stick, plug in, boot from USB.
- **Fresh VirtualBox VM**: VirtualBox UI → New → Linux / Other Linux
  64-bit, ≥ 30 GB disk, 4–8 GB RAM, attach the ISO as the optical drive.
  In *Settings → Network → Adapter 1*, set *Attached to* to **Bridged
  Adapter** so WSL can reach the VM at a LAN IP. (Bridged unavailable?
  Use NAT and add port-forward `Host 2222 → Guest 22`; then SSH to
  `root@<windows-host-lan-ip>:2222` from WSL — not `127.0.0.1`, WSL2
  has its own NAT.)
- **Cloud VM**: most providers expose a NixOS minimal image directly.
  Skip to step 2.

#### 2. Get the target on the network

The minimal ISO is a TTY environment — no GUI network applet, no
NetworkManager. You configure networking by hand. Verify whether
anything is up:

```bash
ip -4 addr show
ping -c 3 1.1.1.1
```

If you already see an `inet` on `enp…`/`eth…`/`wlan…` and ping works,
skip to step 3.

**Wired Ethernet** — DHCP is automatic. If `ip` shows nothing on the
wired interface:

```bash
sudo systemctl restart systemd-networkd
```

**Wi-Fi** — the minimal ISO ships `iwd` (since 23.05). Drop into the
interactive shell:

```bash
iwctl
[iwd]# device list                     # note the station, e.g. wlan0
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect "<SSID>"  # prompts for passphrase
[iwd]# exit
```

Re-check `ip -4 addr show` for the wlan IP.

**USB tethering off your phone** — easiest. Plug a USB cable, enable
USB tethering on the phone; a new `usb0`/`enp…u…` interface appears and
DHCPs immediately. Same for "wired" tethering on iPhones. No Wi-Fi
config needed.

**DNS broken but ping by IP works** — drop a resolver:

```bash
echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
```

#### 3. Enable SSH on the target

The installer's `nixos` user has no password and `root` SSH with
password is disabled by default. Pick one of:

**Option A — password auth** (quickest, fine for a one-shot install):

```bash
sudo passwd                                                            # set root password
sudo sed -i 's/^#*\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

Sanity-check from WSL: `ssh root@<target-ip>` → log in with the
password → `exit`.

**Option B — public-key auth** (no password prompts during the
nixos-anywhere run; preferred):

On the target, set a password for the `nixos` user and start sshd:

```bash
sudo passwd nixos
sudo systemctl start sshd
```

From WSL, copy your key over once:

```fish
ssh-copy-id nixos@<target-ip>            # uses the password you just set
ssh-copy-id root@<target-ip>             # nixos-anywhere uses root by default
```

After this, `ssh root@<target-ip>` should drop straight to a shell.

If you do this kind of install often, jump to step 7 — building a
custom installer ISO with sshd and your key pre-baked turns this whole
step into nothing.

#### 4. Pick a partitioning strategy

**Recommended: declarative partitioning with disko.** The flake already
ships disko as an input and adds `disko.nixosModules.default` to
`commonNixosModules` (see `flake.nix`). Two ready-made layouts live
under `nixos/disko/`:

- `nixos/disko/single-disk-uefi.nix` — GPT, 512 MiB ESP at `/boot`,
  ext4 root at `/`. Pairs with systemd-boot. Use this for any UEFI
  target (modern bare metal, VirtualBox VMs created with "Enable EFI"
  ticked, most cloud images).
- `nixos/disko/single-disk-bios.nix` — GPT with a 1 MiB BIOS-boot
  partition + ext4 root. Pairs with GRUB on `/dev/sda`. Use this for
  VirtualBox VMs created without "Enable EFI" (the default), or older
  bare metal without UEFI firmware.

Both are designed to coexist with the impermanence wipe-root pattern
(`nixos/modules/impermanence-wipe.nix`): wipe-root preserves top-level
`nix` and `boot`, so `/boot` (bootloader) and `/nix/persist`
(impermanence's persisted-paths source) survive every boot. No
subvolumes, no swap, no LVM — same shape as the OVA/QEMU layouts.

To install a profile onto a target, you don't write the host folder
from scratch — copy the template instead:

```bash
cp -r nixos/hosts/_template-bare-metal nixos/hosts/<your-host>
```

Then copy the matching `_template-bare-metal` block in `flake.nix`
(tagged `TEMPLATE — DO NOT EDIT, DO NOT DEPLOY`) to a new key with the
same name as your folder, and set `hostname = "<your-host>"`. Tweak the
copied `default.nix` to switch UEFI ↔ BIOS, override the disk device,
or add host-specific bootloader/kernel/hardware tweaks. The leading
underscore on the template signals "skeleton only — never deploy this
key directly"; leave the template files untouched so they stay a clean
reference.

The copied `default.nix` already includes a `pathExists` guard for
`hardware-configuration.nix`, so the flake evaluates fine before the
hardware config exists. `nixos-anywhere` generates that file for you in
step 5 below, the guard flips, and both files are imported on
subsequent rebuilds.

Note for `nixos-vbox`: the existing OVA-targeting profile gets its
`fileSystems` from `nixos/platforms/vm-virtualbox.nix` and would clash
with disko if you imported one of the disk files into it. To install
the same configuration onto a real disk via `nixos-anywhere`, define a
sibling profile in `flake.nix` (e.g. `nixos-vbox-metal`) with
`hypervisor = "none"`, then import a disko layout from
`nixos/hosts/nixos-vbox-metal/default.nix`.

**Alternative: manual partitioning.** Skip the disko import and
partition the target by hand before running `nixos-anywhere`. On the
target:

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

#### 5. Run `nixos-anywhere` from WSL

With disko (step 4 declarative path):

```fish
nixos-anywhere \
  --flake .#<profile-name> \
  --generate-hardware-config nixos-generate-config nixos/hosts/<profile-name>/nixos/hardware-configuration.nix \
  root@<target-ip>
```

Without disko (step 4 manual path):

```fish
nixos-anywhere \
  --flake .#<profile-name> \
  --no-disko \
  --phases install,reboot \
  --generate-hardware-config nixos-generate-config nixos/hosts/<profile-name>/nixos/hardware-configuration.nix \
  root@<target-ip>
```

`--generate-hardware-config nixos-generate-config <path>` SSHes into the
target, runs `nixos-generate-config`, and writes the result back into
your flake checkout so the next rebuild has the right kernel modules,
microcode, and root-FS UUID baked in.

Either way, `nixos-anywhere` will:
1. Build the system closure locally.
2. Stream it to the target over SSH.
3. Run `nixos-install` against the disko (or pre-mounted) layout.
4. Reboot. The target comes back up as your flake profile.

Total wall time on a warm `/nix/store`: 5–15 minutes.

#### 6. After install

The target is now a normal NixOS host running your profile. Log in as
`david` with the password from `users.users.david.initialPassword`
(`nixos` per `nixos/base.nix`). Change it with `passwd`. From this
point on, treat the machine like any other remote — push updates with
`nixos-rebuild`:

```fish
sudo nixos-rebuild switch --flake .#<profile-name> \
  --target-host david@<target-ip> --use-remote-sudo
```

Commit the generated `hardware-configuration.nix`:

```fish
git add nixos/hosts/<profile-name>/nixos/hardware-configuration.nix
git commit -m "Add hardware-configuration for <profile-name>"
```

Drop `--generate-hardware-config` from future `nixos-anywhere` runs —
the committed file is the source of truth from now on.

#### 7. Optional: bake a custom installer ISO

If you do remote installs often, build a minimal ISO with sshd already
on, your SSH key already trusted, and (optionally) Wi-Fi credentials
already loaded — booting it is then the entire setup.

Create `nixos/installer-iso.nix`:

```nix
{modulesPath, ...}: {
  imports = [(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")];

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAA... david@wsl"   # your WSL public key
  ];

  # Optional: pre-load Wi-Fi credentials so it auto-connects.
  networking.wireless.enable = true;
  networking.wireless.networks."<SSID>".psk = "<passphrase>";
}
```

Wire it as a flake output (in `flake.nix`, alongside the
`nixosConfigurations` block):

```nix
nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [./nixos/installer-iso.nix];
};
```

Build the ISO:

```fish
nix build .#nixosConfigurations.installer.config.system.build.isoImage
ls result/iso/                       # nixos-*.iso
```

Write to USB (`dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M
status=progress`) or attach as the optical drive in VirtualBox. After
boot, the host has an IP, sshd up, and your key trusted — go straight
to step 5 (`nixos-anywhere root@<ip>`).

#### Troubleshooting

- **`nixos-anywhere` errors about missing `disko.devices`** → either
  finish step 4 (declarative) or pass `--no-disko --phases install,reboot`
  after manual partitioning.
- **No IP on the target** → step 2 wasn't applied. Wired: re-run
  `sudo systemctl restart systemd-networkd` and check the cable. Wi-Fi:
  `iwctl` → `station wlan0 connect "<SSID>"`. Quickest fallback: USB-
  tether off your phone.
- **`ping 1.1.1.1` works but `ping nixos.org` fails** → DNS isn't set.
  `echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf`.
- **`Permission denied (publickey,password)`** → `sudo passwd` wasn't
  run on the target, sshd isn't running, or `PermitRootLogin` is still
  `prohibit-password`. Re-do step 3 (Option A flips the sshd_config
  line for you).
- **`Failed to find an installation root`** (manual-partition path) →
  you forgot `mount /dev/disk/by-label/nixos /mnt` (and `/mnt/boot`).
- **First boot stops in stage 1 / "no init found"** → bootloader
  doesn't match the firmware. UEFI VM: `boot.loader.systemd-boot.enable
  = true`. BIOS VM (VirtualBox default): `boot.loader.grub.device =
  "/dev/sda"`. Fix the host module, re-run `nixos-anywhere`.
- **`hardware-configuration.nix` keeps regenerating on every reinstall**
  → drop `--generate-hardware-config` after the first install. Commit
  the file; future runs read it from the flake.
- **WSL can't reach the target's IP** → for VirtualBox + bridged
  adapter, both the Windows host and the VM must be on the same LAN;
  WSL2 with `networkingMode=mirrored` (see `.wslconfig` in step 5 of
  the WSL host setup section) shares that LAN. Without mirrored
  networking, use NAT + port-forward to the *Windows host's* LAN IP.

## Per-profile host configuration

Each profile can have a matching folder at `nixos/hosts/<profile-name>/`.
If a `default.nix` exists there, `mkProfile` imports it automatically — no
flake edits required. This is the place for host-specific modules that
don't belong in the shared tree (hardware quirks, bootloader overrides,
partitions, filesystems, custom kernel params, etc.).

Layout:

```text
nixos/hosts/
  _template-bare-metal/      # SKELETON — copy, don't edit. See below.
    default.nix              # NixOS-side host entry (auto-imported)
    home.nix                 # HM-side host entry (auto-imported)
    nixos/                   # NixOS sub-modules used only by this host
    home/                    # HM sub-modules used only by this host
  nixos-desktop/
    default.nix              # auto-imported for `nixos-desktop`
    nixos/
      hardware-configuration.nix  # generated on the target, see below
```

`mkProfile` looks up both files independently: `default.nix` is added to
the NixOS module list, `home.nix` is added to the Home Manager imports.
Drop either (or both) into a host folder to add per-profile config
without touching `flake.nix`.

VM profiles don't need a host folder — their bootloader/filesystems come
from `nixos/platforms/vm-qemu.nix` or `nixos/platforms/vm-virtualbox.nix`.

### Starting from the bare-metal template

`nixos/hosts/_template-bare-metal/` (paired with the `_template-bare-metal`
entry in `flake.nix`) is the canonical starting point for any new
bare-metal profile. The leading underscore signals "skeleton only —
never deploy this key directly". Both the host folder and the flake
entry carry header comments explaining what's wired in (KDE, gaming,
impermanence, disko UEFI layout, hardware-config `pathExists` guard) and
the customization points (UEFI ↔ BIOS layout, disk device override,
where to add per-host kernel/bootloader tweaks). Copy both — directory
and flake entry — to a new name and customize the copy; leave the
template files alone so they stay a clean reference.

### Bare-metal: generating `hardware-configuration.nix`

Bare-metal profiles (`hypervisor = "none"`) need a per-host
`hardware-configuration.nix` with the machine's root-FS identifier,
kernel modules, CPU microcode, and bootloader device. That file cannot
be known ahead of time; it must be generated on the target.

1. Boot the target from a NixOS install ISO, partition/format, and mount
   the root at `/mnt` (or SSH into an already-running NixOS install).

2. Generate the hardware config:

   ```bash
   # during install
   sudo nixos-generate-config --root /mnt --show-hardware-config

   # or on a running system
   sudo nixos-generate-config --show-hardware-config
   ```

3. Redirect the output into the host folder on your workstation and
   commit it:

   ```bash
   ssh <user>@<remote> 'sudo nixos-generate-config --show-hardware-config' \
     > nixos/hosts/<profile-name>/nixos/hardware-configuration.nix
   git add nixos/hosts/<profile-name>/nixos/hardware-configuration.nix
   git commit -m "Add hardware-configuration.nix for <profile-name>"
   ```

4. Rebuild — locally to validate, then remotely to apply:

   ```bash
   nix eval ".#nixosConfigurations.<profile-name>.config.system.build.toplevel.drvPath"
   sudo nixos-rebuild switch --flake .#<profile-name> \
     --target-host <user>@<remote> --use-remote-sudo
   ```

The `default.nix` in each host folder guards the hardware-config import
with `builtins.pathExists`, so the flake keeps evaluating before the
file has been produced (bare-metal profiles will still fail at build
time with a clear `fileSystems`/`boot.loader` assertion — that's the
signal to run step 2).

## Performance notes

### KVM acceleration

Without KVM, VM performance is typically 10-20x slower.

Check membership:

```bash
groups | grep -q kvm && echo "KVM enabled" || echo "You need to join the kvm group"
```

If needed:

```bash
sudo usermod -aG kvm david
```

Then log out and back in.

## Adding a new module

The two evaluators (Home Manager and NixOS) are kept in separate trees:

- `modules/home/` — Home Manager modules (user config/packages, dotfiles,
  user-side persistence, etc.).
- `modules/nixos/` — NixOS modules (system services, kernel, networking,
  desktop suites, etc.).

A module belongs to exactly one of these. There is no shared/dual-context
tree any more — if a feature has both a system-side and a user-side, ship
two files (one in each folder) and import them from their respective
baselines.

The mental model is minimal: every profile gets a fixed baseline, and each
profile can append its own extras via two lists — `extraNixosImports` and
`extraHomeImports`. There are no flags or toggles.

### 1) Create module file

Pick the right tree and create the file there. For a Home Manager module:

```bash
micro modules/home/example.nix
```

Minimal Home Manager module:

```nix
{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    hello
  ];
}
```

For a NixOS module, drop it under `modules/nixos/` instead and use
`environment.systemPackages` / `services.*` / etc.

### 2) Wire module

Decide where it should live:

- Everywhere (baseline for all profiles):
  - Home Manager: add `./modules/home/example.nix` to `imports` in
    `home.nix`.
  - NixOS: add `./modules/nixos/example.nix` to `commonNixosModules` in
    `flake.nix`.
- On every desktop profile (QEMU/VirtualBox/bare-metal desktop):
  - NixOS-style: append to `sharedDesktopProfile.extraNixosImports`.
  - (Home Manager-style: `sharedDesktopProfile` does not hold HM extras
    by default — either add one there or add it per profile below.)
- On a single profile only:
  - Home Manager-style: set `extraHomeImports = [...]` on
    `profiles.<name>`.
  - NixOS-style: set `extraNixosImports = [...]` on `profiles.<name>`
    (this replaces the list inherited from `sharedDesktopProfile`;
    concatenate `sharedDesktopProfile.extraNixosImports ++ [...]` if
    you want to keep the desktop defaults).
- On a single profile only, but the module is genuinely host-specific
  (hardware quirks, dual-boot grub, fan curves, etc.): drop it under
  `nixos/hosts/<name>/nixos/<your-module>.nix` (or `…/home/…` for HM)
  and import it from that host's `default.nix` / `home.nix`. That keeps
  the shared `modules/` trees free of host-specific clutter.

Example — add `./modules/home/example.nix` only to `nixos-desktop` as a
Home Manager import:

```nix
nixos-desktop = sharedDesktopProfile // {
  hostname = "nixos-desktop";
  hypervisor = "none";
  extraHomeImports = [./modules/home/example.nix];
};
```

### 3) Validate

```bash
home-manager switch --flake .#david
sudo nixos-rebuild switch --flake .#nixos-vm
```
