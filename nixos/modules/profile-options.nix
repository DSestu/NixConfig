{lib, ...}: {
  options.profiles.impermanence.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable impermanence persistence wiring for this profile.";
  };
}
