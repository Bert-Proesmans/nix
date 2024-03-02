{ inputs }:
let
  # WARN; Importing attribute 'all-formats' will provide the expected
  # config.formats.<format> attributes coinciding with the documentation.
  # Importing a single nixosModule format will bake that configuration into
  # the toplevel machine configuration!
  generators-all = inputs.nixos-generators.nixosModules.all-formats;
in
{ lib, ... }: {
  imports = [ generators-all ];

  formatConfigs = lib.mkMerge
    (
      [ ]
      ++ (builtins.map
        (format: {
          "${format}" = { ... }: {
            # Drop ~400MB firmware blobs from nix/store, but this will make the machine (probably) not boot on metal!
            hardware.enableRedistributableFirmware = lib.mkForce false;

            # Workarounds
            disko = lib.mkForce { };
          };
        })
        [
          "hyperv"
          "install-iso-hyperv"
          "virtualbox"
          "vmware"
          "vm"
          "vm-bootloader"
          "vm-nogui"
        ])
      ++ (builtins.map
        (format: {
          "${format}" = { lib, ... }: {
            # Faster and almost equally good compression
            isoImage.squashfsCompression = "zstd -Xcompression-level 15";

            # Do not carry the entire package index, this will be downloaded later
            proesmans.nix.references-on-disk = false;
            system.installer.channel.enable = false;

            # No BIOS boot
            isoImage.makeBiosBootable = lib.mkForce false;
            isoImage.makeEfiBootable = lib.mkForce true;

            # No Wifi
            networking.wireless.enable = lib.mkForce false;

            # No docs
            documentation.enable = lib.mkForce false;
            documentation.nixos.enable = lib.mkForce false;

            # No GCC toolchain
            system.extraDependencies = lib.mkForce [ ];

            # If you only need in-tree filesystems
            # boot.supportedFilesystems = lib.mkForce [ ];

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
