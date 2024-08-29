{ ... }: {
  # NOTE; Path below is fixed in tasks.py
  sops.age.keyFile = "/etc/secrets/decrypter.age";

  # Prevent replacing the running kernel without reboot
  security.protectKernelImage = true;

  # WARN; Don't wait for online, it slows boots and rebuilds
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;

  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping + delayed start;
  # `systemctl stop` followed by `systemctl start`
  systemd.services.systemd-networkd.stopIfChanged = false;
  # Services that are only restarted might be not able to resolve when resolved is stopped before
  systemd.services.systemd-resolved.stopIfChanged = false;

  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;
  # Keep dmesg/journalctl -k output readable by NOT logging each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;

  # DO NOT disable dependencies to change the configuration on the host.
  # This will also break nixos-rebuild from a build host!
  # system.switch.enable = false;

  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };
}
