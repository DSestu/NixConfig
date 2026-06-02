{
  description = "Home Manager & NixOS configuration of David";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    plasma-manager,
    impermanence,
    nixos-wsl,
    disko,
    nixgl,
    agenix,
    ...
  }: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        (final: prev: {
          # code-cursor's wrapper does not include libstdc++, so prebuilt
          # .node addons (e.g. DuckDB) that dlopen it via Cursor's nix-store
          # glibc linker fail. Adding it here injects the path into the
          # wrapper so every Cursor launch has it regardless of how it's started.
          code-cursor = prev.code-cursor.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.makeWrapper];
            postFixup =
              (old.postFixup or "")
              + ''
                wrapProgram $out/bin/cursor \
                  --prefix LD_LIBRARY_PATH : "${prev.stdenv.cc.cc.lib}/lib"
              '';
          });
        })
      ];
    };
  in {
    homeConfigurations."david" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      extraSpecialArgs = {inherit nixgl;};

      modules = [
        ./home.nix
        # On non-NixOS hosts — critical for GUI integration:
        {targets.genericLinux.enable = true;}
      ];
    };

    nixosConfigurations = let
      # ═══════════════════════════════════════════════════════════════════
      #  Per-profile recipe (read this first).
      # ═══════════════════════════════════════════════════════════════════
      #
      #  Every profile in the dictionary below is built from FIVE
      #  ingredients, in this order:
      #
      #    1. commonNixosModules    — system-wide baseline (every profile)
      #    2. commonHomeImports     — user-wide baseline   (every profile)
      #    3. host folder           — auto-discovered from nixos/hosts/<name>/
      #                               (default.nix → NixOS, home.nix → HM)
      #    4. impermanence flag     — flips profiles.impermanence.enable on
      #                               and auto-adds modules/home/persistence.nix
      #    5. extras + platform     — extraNixosImports / extraHomeImports
      #                               from the profile entry, plus the
      #                               module for `hypervisor = "..."`
      #
      #  To add a profile: copy an existing entry, rename, tweak. To add
      #  per-profile config without touching this file, drop a default.nix
      #  (NixOS) or home.nix (HM) into nixos/hosts/<name>/.
      # ═══════════════════════════════════════════════════════════════════
      # ─── 1. NixOS baseline (system-wide, every profile) ──────────────
      # `disko.nixosModules.default` is loaded but inert until a host
      # folder imports one of `nixos/disko/single-disk-{uefi,bios}.nix`.
      commonNixosModules = [
        ./nixos/modules/profile-options.nix
        ./nixos/base.nix
        ./nixos/modules/secrets.nix
        ./modules/dual/fish.nix
        agenix.nixosModules.default
        impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
        disko.nixosModules.default
      ];

      # ─── 2. Home Manager baseline (user-wide, every profile) ─────────
      # `home.nix` aggregates all the modules under `modules/home/`.
      commonHomeImports = [
        ./home.nix
      ];

      # ─── Profile dictionary ──────────────────────────────────────────
      # Each profile entry describes the *intent* (hostname,
      # hypervisor, impermanence?, optional extras); see
      # `nixos/profiles.nix` for the table and
      # `nixos/lib/mk-profile.nix` for the composition recipe.
      profiles = import ./nixos/profiles.nix {root = ./.;};

      # ─── mkProfile: assembles a single profile into a nixosSystem ────
      # See `nixos/lib/mk-profile.nix` for the composition recipe. The
      # function is curried over its dependencies so each profile call
      # is just `mkProfile name profile`.
      mkProfile = import ./nixos/lib/mk-profile.nix {
        inherit lib system commonNixosModules commonHomeImports nixos-wsl plasma-manager;
        root = ./.;
      };
    in
      lib.mapAttrs mkProfile profiles;
  };
}
