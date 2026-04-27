{lib, ...}: {
  # In WSL, this user unit may not be available/reloadable during switch.
  services.ssh-agent.enable = lib.mkForce false;

  # Avoid systemd user-unit orchestration during activation in WSL.
  systemd.user.startServices = lib.mkForce false;

  # nix-gc.timer is a user unit; disable HM-managed user timer in WSL.
  nix.gc.automatic = lib.mkForce false;
}
