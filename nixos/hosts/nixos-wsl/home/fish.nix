{...}: {
  programs.fish.shellAliases = {
    nr = "sudo nixos-rebuild switch --flake ~/nixos-config#nixos-wsl";
  };
}