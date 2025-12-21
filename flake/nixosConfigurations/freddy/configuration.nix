{
  lib,
  flake,
  pkgs,
  ...
}:
{
  imports = [
    ./backup.nix
    ./certificates.nix
    ./database.nix
    ./disks.nix
    ./filesystems.nix
    ./hardware-configuration.nix
    ./identity.nix
    ./mail-server.nix
    ./mail-transfer.nix
    ./passwords.nix
    ./private-network.nix
    ./remote-builder.nix
    ./tls-termination.nix
    ./web-security.nix
    ./wiki.nix
    flake.profiles.remote-machine
  ];

  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.sopsSecrets.enable = true;
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;
  proesmans.home-manager.enable = true;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  systemd.services = {
    memory-stress = {
      enable = false;
      description = "memory-stress";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.stress-ng} --vm 1 --vm-bytes 15% --vm-hang 0";
        Restart = "always";
        Type = "exec";
      };
    };

    cpu-stress = {
      enable = false;
      description = "cpu-stress";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.stress-ng} --cpu 8 --cpu-load 15";
        Restart = "always";
        Type = "exec";
      };
    };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
