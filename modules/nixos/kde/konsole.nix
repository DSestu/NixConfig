{
  config,
  pkgs,
  lib,
  ...
}: let
  profileName = "NixDefault";
  colorScheme = "Kali-Dark";
  font = "MesloLGS NF,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";

  toIni = attrs: let
    kv = kvs:
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "${k}=${toString v}") kvs
      );
    topLevel = attrs."" or {};
    sections = removeAttrs attrs [""];
    sectionBlocks =
      lib.mapAttrsToList (s: kvs: "[${s}]\n${kv kvs}") sections;
    blocks =
      (lib.optional (topLevel != {}) (kv topLevel)) ++ sectionBlocks;
  in
    lib.concatStringsSep "\n\n" blocks;
in {
  xdg.dataFile."konsole/${colorScheme}.colorscheme".source = ./konsole/${colorScheme}.colorscheme;

  xdg.dataFile."konsole/${profileName}.profile".text = toIni {
    Appearance = {
      ColorScheme = colorScheme;
      Font = font;
    };
    General = {
      Name = profileName;
      Parent = "FALLBACK/";
    };
  };

  xdg.configFile."konsolerc".text = toIni {
    "" = {MenuBar = "Disabled";};
    "Desktop Entry" = {DefaultProfile = "${profileName}.profile";};
    General = {ConfigVersion = 1;};
    MainWindow = {MenuBar = "Disabled";};
    "Notification Messages" = {
      CloseAllEmptyTabs = "true";
      CloseAllTabs = "true";
    };
  };
}
