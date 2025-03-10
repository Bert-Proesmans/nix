{ lib, pkgs, flake, config, ... }: {
  imports = [
    flake.inputs.microvm.nixosModules.host
  ];

  # The hypervisor infrastructure is ran by the systemd framework
  networking.useNetworkd = true;

  # ERROR; Secrets normally disappear when rebuilding the host, mounted folders outside the
  # secrets directory become empty.
  # Tell SOPS-NIX to not cleanup old generations of secrets.
  sops.keepGenerations = lib.mkForce 0;
  systemd.timers.auto-reboot = {
    description = "Automatically reboot host after succesful NixOS deployment.";
    reloadTriggers = [ config.system.build.toplevel ];
    timerConfig.OnActiveSec = "12h";
    timerConfig.Unit = "reboot.target";
  };

  microvm.host.enable = lib.mkDefault true;
  microvm.autostart = [ ];

  # Provisions space for microvm volume creation
  # AKA store your newly created volumes at /var/cache/microvm/<name>/<volume>
  systemd.services."microvm@".serviceConfig.CacheDirectory = "microvm/%i";

}
