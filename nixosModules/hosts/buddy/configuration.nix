{ modulesPath, lib, config, special, ... }: {

  imports = [
    "${modulesPath}/hardware/video/radeon.nix" # AMD Vega GPU (Radeon = pre-amdgpu)
    special.profiles.server
    special.profiles.hypervisor
    ./hardware-configuration.nix
    ./postgres.nix
    ./immich.nix
    ./nginx.nix
    # ./dns-vm.nix
    # ./sso-vm.nix
    # ./photos-vm.nix
    # ./proxy-vm.nix
  ];

  networking.hostName = "buddy";
  networking.domain = "internal.proesmans.eu";
  proesmans.facts.tags = [ "bare-metal" "hypervisor" ];

  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.home-manager.enable = true;

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

  sops.secrets."cloudflare-proesmans-key" = { };
  sops.secrets."cloudflare-zones-key" = { };
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "bproesmans@hotmail.com";
      dnsProvider = "cloudflare";
      credentialFiles."CLOUDFLARE_DNS_API_TOKEN_FILE" = config.sops.secrets."cloudflare-proesmans-key".path;
      credentialFiles."CLOUDFLARE_ZONE_API_TOKEN_FILE" = config.sops.secrets."cloudflare-zones-key".path;

      # ERROR; The system resolver is very likely to implement a split-horizon DNS.
      # NOTE; Lego uses DNS requests within the certificate workflow. It must use an external DNS directly since
      # all verification uses external DNS records.
      dnsResolver = "1.1.1.1:53";
    };

    certs."idm.proesmans.eu" = {
      # This block requests a wildcard certificate.
      domain = "*.idm.proesmans.eu";
    };

    certs."alpha.proesmans.eu" = {
      # This block requests a wildcard certificate.
      domain = "*.alpha.proesmans.eu";
    };
  };

  # MicroVM has un-nix-like default of true for enable option, so we need to force it on here.
  microvm.host.enable = lib.mkForce true;

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}

