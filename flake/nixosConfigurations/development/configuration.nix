{ pkgs, flake, ... }: {

  imports = [
    ./hardware-configuration.nix
    ./zfs.nix
    ./wip.nix
    flake.profiles.virtual-machine
    flake.profiles.hypervisor
  ];

  proesmans.filesystem.simple-disk.enable = false;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.nix.registry.fat-nixpkgs.enable = true;
  proesmans.nix.garbage-collect.lower-frequency.enable = true;
  proesmans.sopsSecrets.enable = true;
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;
  proesmans.home-manager.enable = true;
  proesmans.vscode.enable = true;
  proesmans.vscode.nix-dependencies.enable = true;

  # This is a build host, so allow building !
  nix.settings.max-jobs = "auto";

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
  # Retain all outputs and derivations. This assists nix-direnv, retaining devshell outputs.
  # Devshells are constructed from the local user context. Those outputs are rooted inside the project directories, and 
  # nix gc doesn't/cannot know those.
  nix.settings.keep-outputs = true;
  nix.settings.keep-derivations = true;

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

  # Override this service for fun and debug profit
  # USAGE; systemctl edit --runtime test
  systemd.services."test".serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";

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

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
