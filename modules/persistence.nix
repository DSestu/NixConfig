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
      ".config/gh"
      ".config/git"

      # --- User data ---
      "Documents"
      "Downloads"
      "Pictures"
      "Videos"
      "projects"

      # --- Shell state ---
      ".local/share/fish"
      ".local/share/atuin"
      ".local/share/zoxide"

      # --- Direnv allow list (else re-approve every repo each boot) ---
      ".local/share/direnv"

      # --- Browser profiles (sessions, cookies, extensions, bookmarks) ---
      ".mozilla"
      ".config/google-chrome"

      # --- IDE settings (not caches/indexes) ---
      ".config/Code - OSS/User"
      ".config/JetBrains"
    ];

    files = [
      ".bash_history"
    ];
  };
}
