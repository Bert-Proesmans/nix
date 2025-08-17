{
  lib,
  ...
}:
{
  imports = [
    ./certificates.nix
    ./disks.nix
    ./hardware-configuration.nix
    ./memory-handling.nix
    ./private-network.nix
    ./tls-termination.nix
  ];

  # Slows down write operations considerably
  nix.settings.auto-optimise-store = lib.mkForce false;

  # Setup runtime secrets and corresponding ssh host key
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.enable = true;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

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

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "25.05";
}
