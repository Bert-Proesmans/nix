{ inputs }:
let
  # WARN; Importing attribute 'all-formats' will provide the expected
  # config.formats.<format> attributes coinciding with the documentation.
  # Importing a single nixosModule format will bake that configuration into
  # the toplevel machine configuration!
  generators-all = inputs.nixos-generators.nixosModules.all-formats;
in
{ config, lib, ... }: {
  imports = [ generators-all ];

  formatConfigs = lib.mkMerge (
    [ ]
    ++ (builtins.map
      (format: {
        "${format}" = { ... }: {
          # Drop ~400MB firmware blobs from nix/store, but this will make the machine (probably) not boot on metal!
          hardware.enableRedistributableFirmware = lib.mkDefault false;

          # Workarounds
          disko = lib.mkForce { };
        };
      })
      [
        "vmware"
        "hyperv"
        "virtualbox"
        "vm"
        "vm-bootloader"
        "vm-nogui"
      ])
    ++ (builtins.map
      (format: {
        "${format}" = { lib, ... }: {
          # Faster and almost equally good compression
          isoImage.squashfsCompression = "zstd -Xcompression-level 6";

          # No Wifi
          networking.wireless.enable = lib.mkForce false;

          # No docs
          documentation.enable = lib.mkForce false;
          documentation.nixos.enable = lib.mkForce false;

          # No GCC toolchain
          system.extraDependencies = lib.mkForce [ ];

          # Workarounds
          disko = lib.mkForce { };
        };
      })
      [
        "install-iso"
        "install-iso-hyperv"
      ])
  );
}
