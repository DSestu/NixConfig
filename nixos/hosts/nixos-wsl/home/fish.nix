{...}: {
  programs.fish.shellAliases = {
    nr = "sudo nixos-rebuild switch --flake /mnt/d/projets_python_ssd/Sencrop/NixConfig#nixos-wsl";
  };
}