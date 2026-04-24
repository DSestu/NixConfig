{modulesPath, ...}: {
  imports = [(modulesPath + "/virtualisation/virtualbox-image.nix")];

  virtualisation.virtualbox.guest.enable = true;
}
