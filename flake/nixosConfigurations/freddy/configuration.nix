{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./boot-unlock.nix
    ./certificates.nix
    ./database.nix
    ./disks.nix
    ./filesystems.nix
    ./hardware-configuration.nix
    ./remote-builder.nix
    ./tls-termination.nix
    ./web-security.nix
    ./wiki.nix
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

  # Make me an admin!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "wheel" # Allows sudo access
      "systemd-journal" # Read the systemd service journal without sudo
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };

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
