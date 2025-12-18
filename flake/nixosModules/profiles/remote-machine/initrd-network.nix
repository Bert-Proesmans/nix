{ config, ... }:
{
  boot.initrd.systemd = {
    enable = true;
    emergencyAccess = false;
    network.wait-online.enable = true;
    network.wait-online.anyInterface = true;
    # Configure interfaces during boot the same as while the host runs.
    network.networks = config.systemd.network.networks;
    network.links = config.systemd.network.links;
  };
}
