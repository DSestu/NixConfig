{
  lib,
  modulesPath,
  ...
}: {
  # Raspberry Pi 3/4/5 via U-Boot + extlinux. Owns bootloader, root FS
  # (label NIXOS_SD) and the image build:
  #   nix build .#nixosConfigurations.nixos-rpi.config.system.build.sdImage
  # Flash result/sd-image/*.img.zst with
  #   zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress
  imports = ["${modulesPath}/installer/sd-card/sd-image-aarch64.nix"];

  # This Pi's host key isn't a recipient in secrets/secrets.nix yet, so
  # it can't decrypt david-password.age and david would have no password.
  # Once it is (harvest /etc/ssh/ssh_host_ed25519_key.pub, add, rekey),
  # delete these two lines.
  users.users.david.hashedPasswordFile = lib.mkForce null;
  users.users.david.initialPassword = "nixos";

  # Protocol multiplexer: one public port, routed by protocol.
  # Add backends here (e.g. { name = "tls"; host = "192.168.1.30"; port = "443"; }).
  services.sslh = {
    enable = true;
    method = "ev";
    settings.protocols = [
      {
        name = "ssh";
        host = "localhost";
        port = "22";
        service = "ssh";
      }
    ];
  };
  networking.firewall.allowedTCPPorts = [443];
}
