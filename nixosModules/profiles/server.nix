{ lib, pkgs, flake-inputs, config, ... }: {
  # NOTE; Path below is fixed in tasks.py
  sops.age.keyFile = "/etc/secrets/decrypter.age";

  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Prevent replacing the running kernel w/o reboot
  security.protectKernelImage = true;
  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;
  # Keep dmesg/journalctl -k output readable by NOT logging
  # each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;
  # Disable dependencies to change the configuration on the host itself.
  system.switch.enable = false;
}
