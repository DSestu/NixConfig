{pkgs, ...}: {
  # Ensure GTK can load kde-gtk-config modules used by Breeze (see gtk-modules in theme settings.ini).
  environment.sessionVariables = {
    GTK_PATH = [ "${pkgs.kdePackages.kde-gtk-config}/lib/gtk-3.0" ];
  };

  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  environment.systemPackages = with pkgs.kdePackages; [
    plasma-systemmonitor
    libksysguard
  ];

  # PipeWire for audio (KDE expects it)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # XDG portal — needed for screen sharing, file pickers, Flatpak integration on Wayland
  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.kdePackages.xdg-desktop-portal-kde];
  };
}
