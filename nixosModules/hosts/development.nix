{ lib, config, pkgs, ... }: {
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";

  networking.hostName = "development";
  networking.domain = "alpha.proesmans.eu";

  proesmans.filesystem.simple-disk.enable = true;
  proesmans.nix.linux-64 = true;
  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.vscode.enable = true;
  proesmans.vscode.nix-dependencies.enable = true;

  # Load Hyper-V kernel modules
  virtualisation.hypervGuest.enable = true;

  # Make me a user!
  users.users.bertp = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ "wheel" ]
      ++ lib.optional config.virtualisation.libvirtd.enable
      "libvirtd" # NOTE; en-GB
      ++ lib.optional config.networking.networkmanager.enable
      "networkmanager";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
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
  ];

  # Note; default firewall package is IPTables
  networking.firewall.allowedTCPPorts = [
    5201 # Allow incoming IPerf traffic when acting as a server
  ];

  # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/networking.nix

  # Networking configuration
  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;

  # Keep dmesg/journalctl -k output readable by NOT logging
  # each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;

  # Use networkd instead of the pile of shell scripts
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.usePredictableInterfaceNames = lib.mkDefault true;

  # The notion of "online" is a broken concept
  # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;

  # FIXME: Maybe upstream?
  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping it with `systemctl stop`
  # followed by a delayed `systemctl start`.
  systemd.services.systemd-networkd.stopIfChanged = false;
  # Services that are only restarted might be not able to resolve when resolved is stopped before
  systemd.services.systemd-resolved.stopIfChanged = false;

  # Hyper-V does not emulate PCI devices, so network adapters remain on their ethX names
  # eth0 receives an address by DHCP and provides the default gateway route
  # eth1 is configured with a stable address for SSH
  networking.interfaces.eth0.useDHCP = true;
  networking.interfaces.eth1.ipv4.addresses = [{
    # V4 link local address
    address = "169.254.245.139";
    prefixLength = 24;
  }];

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
}
