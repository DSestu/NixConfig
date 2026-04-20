{
  config,
  pkgs,
  ...
}: let
  profileName = "NixDefault";
in {
  xdg.dataFile."konsole/${profileName}.profile".text = ''
    [Appearance]
    ColorScheme=Breeze
    Font=MesloLGS NF,11,-1,5,50,0,0,0,0,0

    [General]
    Name=${profileName}
    Parent=FALLBACK/
  '';

  xdg.configFile."konsolerc".text = ''
    [Desktop Entry]
    DefaultProfile=${profileName}.profile
  '';
}
