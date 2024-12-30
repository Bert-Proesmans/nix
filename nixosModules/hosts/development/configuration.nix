{ lib, config, pkgs, special, ... }: {

  imports = [
    special.profiles.hypervisor
    ./hardware-configuration.nix
    ./wip.nix
  ];

  networking.hostName = "development";
  networking.domain = "internal.proesmans.eu";
  proesmans.facts.tags = [ "virtual-machine" "hypervisor" ];

  proesmans.nix.garbage-collect.enable = true;
  # Garbage collect less often, so we don't drop build artifacts from other systems
  proesmans.nix.garbage-collect.development-schedule.enable = true;
  proesmans.nix.registry.nixpkgs.fat = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.vscode.enable = true;
  proesmans.vscode.nix-dependencies.enable = true;
  proesmans.home-manager.enable = true;

  # Customise nix to allow building on this host
  nix.settings.max-jobs = "auto";
  nix.settings.trusted-users = [ "@wheel" ];

  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  sops.age.keyFile = "/etc/secrets/decrypter.age";

  # Override this service for fun and debug profit
  systemd.services."test".serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";

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

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Automatically load development shell in project working directories
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  # Pre-install some tools for debugging network/disk/code
  environment.systemPackages = [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.iperf
    pkgs.dig
    pkgs.traceroute
    pkgs.socat
    pkgs.nmap # ncat
  ];

  # Note; default firewall package is IPTables
  networking.firewall.allowedTCPPorts = [
    5201 # Allow incoming IPerf traffic when acting as a server
  ];

  # Avoid TOFU MITM with github by providing their public key here.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";
  };

  sops.secrets.ssh_host_ed25519_key = {
    path = "/etc/ssh/ssh_host_ed25519_key";
    owner = config.users.users.root.name;
    group = config.users.users.root.group;
    mode = "0400";
    restartUnits = [ config.systemd.services.sshd.name ];
  };

  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  microvm.host.enable = lib.mkForce true;

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
