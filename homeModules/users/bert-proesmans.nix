{ osConfig, ... }:
{
  # Values are preset for the next attribute names;
  # - home.username
  # - home.homeDirectory
  imports = [ ];

  # Make the home-manager CLI/tools available to the user
  # programs.home-manager.enable = true;

  programs.bash.enable = true;

  # Automatically activate developer environment when entering project folders.
  # programs.direnv.enable = true;
  # programs.direnv.nix-direnv.enable = true;

  programs.git = {
    enable = true;
    userName = "Bert Proesmans";
    userEmail = "bproesmans@hotmail.com";

    extraConfig = { };
  };

  # Ignore below
  home.stateVersion = "23.11";
}
