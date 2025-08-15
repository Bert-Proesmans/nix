{ flake, ... }:
{
  imports = [
    ./backup.nix
    ./certificates.nix
    ./computer-backup.nix
    ./database.nix
    ./disks.nix
    ./dns.nix
    ./filesystems.nix
    ./hardware-configuration.nix
    ./identity.nix
    ./pictures.nix
    ./tls-termination.nix
    flake.profiles.hypervisor
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
      "kvm" # Interact with forwarded VSOCK files
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };

  # Temporary, will be moved to proxy-vm later
  # sops.secrets.tailscale_connect_key.owner = "root";
  # services.tailscale = {
  #   enable = true;
  #   disableTaildrop = true;
  #   openFirewall = true;
  #   useRoutingFeatures = "none";
  #   authKeyFile = config.sops.secrets.tailscale_connect_key.path;
  #   extraDaemonFlags = [ "--no-logs-no-support" ];
  # };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
