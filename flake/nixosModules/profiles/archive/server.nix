{ ... }:
{
  # NOTE; Path below is fixed in tasks.py
  sops.age.keyFile = "/etc/secrets/decrypter.age";

  # Prevent replacing the running kernel without reboot
  security.protectKernelImage = true;

  networking.useNetworkd = true;
  # WARN; Don't wait for online, our servers should service requests asap independantly from online status!
  # This unit also slows down boot times, rebuilds, and introduces lots of jitter in those timings.
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
    extraGroups = [
      "systemd-journal" # Read the systemd service journal without sudo
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };
}
