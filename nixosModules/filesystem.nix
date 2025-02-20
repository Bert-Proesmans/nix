# Simple hardware and disk configuration for physicl/virtual machines
{ lib, special, config, options, ... }:
let
  cfg = config.proesmans.filesystem;
in
{
  imports = [ special.inputs.disko.nixosModules.disko ];

  options.proesmans.filesystem = {
    simple-disk.enable = lib.mkEnableOption (lib.mdDoc "Enable a simple disk layout");
    simple-disk.device = lib.mkOption {
      default = "/dev/sda";
      type = lib.types.str;
      description = lib.mdDoc "The name of the one disk to format";
    };
  };

  config = lib.mkIf cfg.simple-disk.enable {
    assertions = [{
      assertion = builtins.stringLength cfg.simple-disk.device > 0;
      message = ''
        A device path must be provided for formatting to work!
        Set one at 'proesmans.filesystem.simple-disk.device'.
      '';
    }];

    # EFI boot!
    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.systemd-boot.editor = lib.mkDefault false;

    # Cleaning tmp directory not required if it's a tmpfs
    # Enabling tmpfs for tmp also prevents additional SSD writes
    boot.tmp.cleanOnBoot = lib.mkDefault (!config.boot.tmp.useTmpfs);

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
