{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/qemu-vm.nix"];

  virtualisation.memorySize = 4096;
  virtualisation.cores = 4;
  virtualisation.diskSize = 20480;

  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  users.users.alice = {
    isNormalUser = true;
    password = "test";
    extraGroups = ["wheel"];
  };

  environment.systemPackages = with pkgs; [firefox kate ripgrep];

  system.stateVersion = "24.11";
}
