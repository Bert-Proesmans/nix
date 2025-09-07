# Simple hardware and disk configuration for physicl/virtual machines
{
  lib,
  flake,
  config,
  ...
}:
let
  cfg = config.proesmans.filesystem;
in
{
  imports = [ flake.inputs.disko.nixosModules.disko ];

  options.proesmans.filesystem = {
    simple-disk.enable = lib.mkEnableOption "Enable a simple disk layout";
    simple-disk.device = lib.mkOption {
      default = "/dev/sda";
      type = lib.types.str;
      description = "The name of the one disk to format";
    };
  };

  config = lib.mkIf cfg.simple-disk.enable {
    assertions = [
      {
        assertion = builtins.stringLength cfg.simple-disk.device > 0;
        message = ''
          A device path must be provided for formatting to work!
          Set one at 'proesmans.filesystem.simple-disk.device'.
        '';
      }
    ];

    disko.devices = {
      disk.root = {
        device = cfg.simple-disk.device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            encryptedSwap = {
              size = "2G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };

          };
        };
      };
      lvm_vg = {
        pool = {
          type = "lvm_vg";
          lvs = {
            root = {
              size = "100%FREE";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "defaults" ];
              };
            };
          };
        };
      };
    };
  };
}
