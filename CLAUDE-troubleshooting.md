# Troubleshooting — known fixes

## Steam on the non-NixOS workstation: `bwrap: Can't find source path /etc/zoneinfo`

**Symptom:** `steam` (Home Manager install, `homeConfigurations.david`)
exits straight away with
`bwrap: Can't find source path /etc/zoneinfo: No such file or directory`.

**Cause:** the nixpkgs `buildFHSEnv` wrapper for Steam always passes
`--bind /etc/zoneinfo /usr/share/zoneinfo`, which assumes NixOS has
created `/etc/zoneinfo`. Debian-family hosts (Kali here) keep tzdata in
`/usr/share/zoneinfo` and have no `/etc/zoneinfo`.

**Fix (once per host, outside this repo):**

```sh
sudo ln -s /usr/share/zoneinfo /etc/zoneinfo
```

Undo with `sudo rm /etc/zoneinfo`. Verified 2026-11-22 on Kali with
`steam-1.0.0.87`. When nixpkgs switches that bind to `--bind-try`, the
symlink can go.
