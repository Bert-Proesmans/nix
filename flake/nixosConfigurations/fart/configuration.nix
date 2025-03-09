{ config, special, ... }: {

  imports = [
    special.profiles.server
    ./hardware-configuration.nix
  ];

  networking.hostName = "fart";
  networking.domain = "internal.proesmans.eu";

  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.home-manager.enable = false;

  sops.defaultSopsFile = ./secrets.encrypted.yaml;

  # Make me an admin user!
  users.users.bert-proesmans.extraGroups = [ "wheel" ];

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  sops.secrets.ssh_host_ed25519_key = {
    path = "/etc/ssh/ssh_host_ed25519_key";
    owner = config.users.users.root.name;
    group = config.users.users.root.group;
    mode = "0400"; # Required by sshd
    restartUnits = [ config.systemd.services.sshd.name ];
  };

  services.openssh.hostKeys = [
    {
      path = config.sops.secrets.ssh_host_ed25519_key.path;
      type = "ed25519";
    }
  ];

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "25.05";
}
