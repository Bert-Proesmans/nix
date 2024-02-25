{ modulesPath, lib, config, inputs, pkgs, ... }: {
  imports = [
    "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    inputs.srvos.nixosModules.common
  ];

  system.stateVersion = config.system.nixos.version;

  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # NOTE; Empty first line is intentional
  services.getty.helpLine = lib.mkAfter ''

    \4    \6
    ---
    eth0; \4{eth0}    \6{eth0}
    eth1; \4{eth1}    \6{eth1}
    eth2; \4{eth2}    \6{eth2}
  '';

  # Not really needed. Saves a few bytes and the only service we are running is sshd, which we want to be reachable.
  networking.firewall.enable = false;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.dhcpcd.enable = false;

  systemd.network.networks."10-uplink" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
      LLMNR = "yes";
      EmitLLDP = "yes";
      IPv6AcceptRA = "yes";
      MulticastDNS = "yes";
      LinkLocalAddressing = "yes";
      LLDP = "yes";
    };

    dhcpV4Config = {
      UseHostname = false;
      ClientIdentifier = "mac";
    };
  };

  systemd.services.log-network-status = {
    wantedBy = [ "multi-user.target" ];
    # No point in restarting this. We just need this after boot
    restartIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      ExecStart = [
        # Allow failures, so it still prints what interfaces we have even if we
        # not get online
        "-${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online"
        "${pkgs.iproute2}/bin/ip -c addr"
        "${pkgs.iproute2}/bin/ip -c -6 route"
        "${pkgs.iproute2}/bin/ip -c -4 route"
        "${pkgs.systemd}/bin/networkctl status"
      ];
    };
  };

}
