# System-wide NixOS baseline applied to every profile (see
# `commonNixosModules` in flake.nix).
#
# This file owns:
#   - System-wide impermanence persistence map (paired with
#     `modules/home/persistence.nix` for the user-side equivalent).
#   - Common system services, user account, locale, nix settings, GC.
#
# Per-profile NixOS extras go via `extraNixosImports` or the host
# folder's `default.nix`, not here.
{
  config,
  lib,
  pkgs,
  ...
}: {
  nixpkgs.config.allowUnfree = true;

  imports = [];

  # Impermanence: `/` is wiped on every boot by the platform-level wipe-root
  # service, so anything we want to survive a reboot has to be listed here.
  # `environment.persistence` bind-mounts these paths from /nix/persist back
  # into the running root.
  environment.persistence = lib.mkIf config.profiles.impermanence.enable {
    "/nix/persist" = {
      hideMounts = true;
      directories = [
        # UID/GID stability and NixOS state.
        "/var/lib/nixos"
        # Logs.
        "/var/log"
        "/var/lib/systemd/coredump"
        # Network state — saved Wi-Fi, VPNs, DHCP leases, etc.
        "/etc/NetworkManager/system-connections"
        "/var/lib/NetworkManager"
        # Bluetooth pairings, color profiles, power state.
        "/var/lib/bluetooth"
        "/var/lib/colord"
        "/var/lib/upower"
      ];
      files = [
        # System identity. Without a stable machine-id, every boot looks
        # like a brand-new host to systemd-journald, NetworkManager, etc.
        "/etc/machine-id"
        # SSH host keys. Without these, every reboot regenerates the host
        # key and triggers "REMOTE HOST IDENTIFICATION HAS CHANGED" on
        # every client that has connected before.
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
        # Persist password changes made via `passwd`. Combined with
        # `users.mutableUsers = true` (the NixOS default), this lets
        # `initialPassword` seed the first boot and any subsequent
        # password change survives wipe-root.
        "/etc/shadow"
      ];
    };
  };

  services.xserver.xkb.layout = "fr";
  console.keyMap = "fr";

  users.users.david = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  # Use fish for root too. Tradeoff: fish isn't POSIX, so any script that
  # invokes `sh -c '...'` is unaffected (sh stays dash/bash via the
  # platform default), but interactive root sessions (`sudo -i`,
  # `sudo su -`) get the Tide-themed fish defined in
  # modules/common/fish.nix instead of bash. Single-shot `sudo <cmd>`
  # invocations don't spawn a shell at all, so they're untouched.
  users.users.root.shell = pkgs.fish;

  services.openssh.enable = true;

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "david";
  };

  environment.systemPackages = [];

  system.stateVersion = "25.11";
}
