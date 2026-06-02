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
        # NOTE: /etc/shadow is NOT in this list — see the dedicated
        # copy-on-change persistence block below for why a bind mount
        # can't survive `passwd` or NixOS users activation.
      ];
    };
  };

  # /etc/shadow persistence (copy-on-change, not bind mount).
  #
  # Why not a bind mount? Both NixOS' `update-users-groups.pl` (run from
  # `stage-2-init.sh` before systemd starts) and shadow-utils' `passwd`
  # rewrite /etc/shadow via atomic `rename(2)`. That unlinks the inode
  # the bind mount points at and replaces it with a new one — subsequent
  # writes never reach /nix/persist. impermanence's file persistence
  # therefore can't be used here.
  #
  # Two-part design:
  #   1. Activation script (after `users`) copies /nix/persist/etc/shadow
  #      back over the freshly-generated /etc/shadow if the persisted
  #      copy exists. So a previously-set password wins over the
  #      activation-time `initialPassword` reseed.
  #   2. A `systemd.path` unit watches /etc/shadow for changes and copies
  #      it to /nix/persist/etc/shadow. Catches `passwd`, `chpasswd`,
  #      `usermod -p`, and the activation rewrite itself (which is
  #      harmless — same content goes back out).
  #
  # First boot: /nix/persist/etc/shadow doesn't exist, activation seeds
  # /etc/shadow from `initialPassword`, the path unit fires, and the
  # seeded shadow is captured. From then on, password changes round-trip.
  system.activationScripts.restorePersistedShadow = lib.mkIf config.profiles.impermanence.enable {
    text = ''
      if [ -f /nix/persist/etc/shadow ]; then
        ${pkgs.coreutils}/bin/install -m 0640 -o root -g shadow \
          /nix/persist/etc/shadow /etc/shadow
      fi
    '';
    deps = ["users"];
  };

  # Trigger a snapshot of /etc/shadow → /nix/persist whenever /etc/shadow
  # changes. `PathModified` is important: `passwd` writes a temp file and
  # atomically renames it over /etc/shadow; `PathChanged` (CLOSE_WRITE on
  # the original inode) does not reliably observe this because the
  # watched inode is unlinked by the rename.
  systemd.paths.persist-etc-shadow = lib.mkIf config.profiles.impermanence.enable {
    description = "Watch /etc/shadow for changes and trigger persist";
    wantedBy = ["multi-user.target"];
    pathConfig = {
      PathModified = "/etc/shadow";
      Unit = "persist-etc-shadow.service";
    };
  };

  # Snapshot service triggered by the path unit on every change. Must NOT
  # use `RemainAfterExit` — that would leave the service in `active
  # (exited)` after the first run, and subsequent path-unit triggers
  # would be no-ops (systemd skips activations of already-active units),
  # so the very first `passwd` after boot wouldn't be persisted.
  systemd.services.persist-etc-shadow = lib.mkIf config.profiles.impermanence.enable {
    description = "Copy /etc/shadow to /nix/persist";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/install -D -m 0640 -o root -g shadow /etc/shadow /nix/persist/etc/shadow";
    };
  };

  # Safety net: also snapshot at shutdown, so a `passwd` change immediately
  # followed by `reboot` (before inotify quiesces) still lands on disk.
  # Separate unit so it can use `RemainAfterExit` for the
  # `ExecStop`-on-shutdown pattern without breaking the change-driven
  # service above.
  systemd.services.persist-etc-shadow-shutdown = lib.mkIf config.profiles.impermanence.enable {
    description = "Snapshot /etc/shadow to /nix/persist at shutdown";
    wantedBy = ["multi-user.target"];
    before = ["shutdown.target"];
    conflicts = ["shutdown.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${pkgs.coreutils}/bin/install -D -m 0640 -o root -g shadow /etc/shadow /nix/persist/etc/shadow";
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
  # modules/dual/fish.nix instead of bash. Single-shot `sudo <cmd>`
  # invocations don't spawn a shell at all, so they're untouched.
  #
  # `initialPassword` is the escape hatch: NixOS ships with `root` locked
  # by default, so a failed boot drops to emergency mode where nobody can
  # log in. Seeding a password lets you actually use the rescue shell.
  # On wipe-root profiles, `passwd` changes survive reboots via the
  # `/etc/shadow` copy-on-change watcher above; `initialPassword` only
  # seeds first boot.
  users.users.root = {
    shell = pkgs.fish;
    initialPassword = "nixos";
  };

  services.openssh.enable = true;
  # SSH posture is enforced at the baseline. Network access is
  # key-only and root is never allowed via SSH — local console + sudo
  # are the only ways into the root account. Any profile that needs
  # to override these has to argue for it; the default does not bend.
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = false;
  };

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

  # nix-ld: compatibility shim so FHS binaries (VS Code/Cursor extensions,
  # prebuilt .node addons like DuckDB) can dlopen standard libs such as
  # libstdc++.so.6 that don't exist at /usr/lib on NixOS.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++, libgcc_s
    ];
  };

  environment.systemPackages = [];

  system.stateVersion = "25.11";
}
