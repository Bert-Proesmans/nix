{ lib, config, ... }:
let cfg = config.virtualisation; # NOTE; en-GB
in {
  config = lib.mkIf
    (cfg.hypervGuest.enable || cfg.vmware.guest.enable || cfg.virtualbox.guest.enable)
    {
      # Drop ~400MB firmware blobs from nix/store, but this will make the machine (probably) not boot on metal!
      hardware.enableRedistributableFirmware = lib.mkDefault false;
    };
}
