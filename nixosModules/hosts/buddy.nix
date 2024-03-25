{ lib, pkgs, config, ... }: {

  networking.hostName = "buddy";
  networking.domain = "alpha.proesmans.eu";

  proesmans.filesystem.simple-disk.enable = true;
  proesmans.filesystem.simple-disk.device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_120GB_S21UNSBG116809J";
  proesmans.nix.linux-64 = true;
  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.home-manager.enable = true;

  # Make me a user!
  users.users.bert-proesmans = {
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

  # Networking configuration
  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;

  # Keep dmesg/journalctl -k output readable by NOT logging
  # each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;

  # Use networkd instead of the pile of shell scripts
  networking.useNetworkd = true;
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

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
