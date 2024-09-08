{ lib, pkgs, config, ... }: {
  networking.domain = "alpha.proesmans.eu";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  networking.firewall.allowedTCPPorts = [ 80 443 ];



  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
