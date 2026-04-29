# Home-wide persistence configuration
# This file is used to configure the persistence whitelist of the user's home directory
# This is used in par with /nixos/base.nix to configure the persistence whitelist of the root directory (system-wide persistence)
{
  config,
  lib,
  ...
}: {
  home.persistence."/nix/persist" = {
    directories = [
      # --- Secrets & identity ---
      {
        directory = ".ssh";
        mode = "0700";
      }
      {
        directory = ".gnupg";
        mode = "0700";
      }
      "nixconfig"

      ".config/gh"
      ".config/git"

      # --- User data ---
      "Documents"
      "Downloads"
      "Pictures"
      "Videos"
      "github"

      # --- Shell state ---
      ".local/share/fish"
      ".local/share/atuin"
      ".local/share/zoxide"

      # --- Direnv allow list (else re-approve every repo each boot) ---
      ".local/share/direnv"

      # --- Browser profiles (sessions, cookies, extensions, bookmarks) ---
      ".config/google-chrome"
      ".config/BraveSoftware"

      # --- Game launchers ---
      ".local/share/Steam"
      ".config/gdlauncher_next"
      ".local/share/gdlauncher_next"

      # --- IDE settings (not caches/indexes) ---
      ".config/Code/User"
      ".config/Cursor/User"
    ];

    files = [];
  };
}
