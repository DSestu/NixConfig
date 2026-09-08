# WSL host setup (run once)

If you build this flake from WSL on Windows, do this setup **before the
first build**. Skipping it produces a pathological failure mode: a Nix
build that should take minutes pegs one CPU at 99% for hours, because
Windows antivirus is scanning every single write into the WSL
`ext4.vhdx`.

You only ever do this once per Windows machine.

- [1. Confirm KVM is exposed to WSL](#1-confirm-kvm-is-exposed-to-wsl)
- [2. Locate every WSL distro's `ext4.vhdx`](#2-locate-every-wsl-distros-ext4vhdx)
- [3. Exclude WSL from Windows Defender](#3-exclude-wsl-from-windows-defender)
- [4. Exclude WSL from third-party antivirus](#4-exclude-wsl-from-third-party-antivirus)
- [5. Configure WSL2 resources and networking](#5-configure-wsl2-resources-and-networking)
- [6. Confirm `/nix` is on real ext4](#6-confirm-nix-is-on-real-ext4)

---

## 1. Confirm KVM is exposed to WSL

Inside WSL:

```bash
ls -la /dev/kvm
```

Expect a character device with `crw-rw-rw-` permissions. Without it,
every QEMU VM in this repo runs 10–20× slower (see the
[KVM note](../readme.md#running-the-vms)).

If it's missing, enable nested virtualization on the Windows side
(PowerShell **as Administrator**):

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --update
wsl --shutdown
```

Reboot if Intel VT-x / AMD-V is disabled in your BIOS.

## 2. Locate every WSL distro's `ext4.vhdx`

`wsl --import`-style distros (NixOS-WSL, most commonly) live wherever
you placed them at import time — *not* under `AppData\Local\Packages`.
List them all:

```powershell
Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss |
  ForEach-Object { Get-ItemProperty $_.PSPath } |
  Select-Object DistributionName, BasePath
```

Note every `BasePath` — there's an `ext4.vhdx` inside each. Then catch
the Microsoft Store distros too:

```powershell
(Get-ChildItem $env:USERPROFILE\AppData\Local\Packages -Filter ext4.vhdx -Recurse).FullName
```

Keep the full list of paths handy — the next two steps need it.

## 3. Exclude WSL from Windows Defender

PowerShell **as Administrator**. Repeat the first `Add-MpPreference`
line once per `BasePath` from step 2:

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

## 4. Exclude WSL from third-party antivirus

Defender exclusions do **nothing** for third-party AV (Avast, AVG,
Norton, McAfee, Kaspersky, …). Add the same paths to whichever you have
installed. For Avast specifically: Menu → Settings → General →
Exceptions → add each `ext4.vhdx`, the `BasePath` parent directories,
and `\\wsl$`.

Sanity check: pause the AV shields for 10 minutes and run a build. If it
suddenly flies, that AV is missing exclusions.

## 5. Configure WSL2 resources and networking

Create `C:\Users\<you>\.wslconfig` on the Windows side:

```ini
[wsl2]
memory=24GB
processors=12
swap=8GB
networkingMode=mirrored
```

Tune `memory`/`processors` to leave Windows roughly 8 GB and a couple of
cores. `networkingMode=mirrored` requires WSL ≥ 2.0.0 (`wsl --version`
to check) — it avoids substituter hangs caused by WSL's default NAT, and
it's what lets WSL reach a bridged VirtualBox VM on your LAN during a
[bare-metal install](install-bare-metal.md).

Apply it:

```powershell
wsl --shutdown
```

Reopen the WSL shell and verify from inside:

```bash
nproc
free -h
```

## 6. Confirm `/nix` is on real ext4

Inside WSL:

```bash
df -h /nix/store
mount | grep '/nix'
```

The `Filesystem` column must be a real block device (`/dev/sdX`), **not**
`drvfs` and not a Windows path. If `/nix` sits on a Windows path you'll
pay a 10–100× penalty on every store operation; move the distro or
reinstall it inside the Linux filesystem before going any further.

---

## Related

- [Daily commands](../readme.md#daily-commands) — including
  `nix-store --repair`, which you'll eventually need: the `ext4.vhdx`
  takes damage from abrupt Windows shutdowns.
- [Installing a bare-metal machine](install-bare-metal.md) — the
  networking notes there assume `networkingMode=mirrored` from step 5.
