# This is a lambda. Any -> (Any -> Any)
{ inputs }:
let
  disko-module = inputs.disko.nixosModules.disko;
in
# This is a nixos module. NixOSArgs -> AttrSet
{ config, lib, options, ... }:
let
  cfg = config.proesmans.filesystem;
in
{
  imports = [ disko-module ];

  options.proesmans.filesystem = {
    simple-disk.enable = lib.mkEnableOption (lib.mdDoc "Enable a simple disk layout");
    simple-disk.device = lib.mkOption {
      default = "/dev/sda";
      type = lib.types.str;
      description = lib.mdDoc "The name of the one disk to format";
    };
    simple-disk.systemd-boot.enable = lib.mkEnableOption (lib.mdDoc "Use the systemd bootloader");
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.simple-disk.enable {
      # Cleaning tmp directory not required if it's a tmpfs
      # Enabling tmpfs for tmp also prevents additional SSD writes
      boot.tmp.cleanOnBoot = lib.mkDefault (!config.boot.tmp.useTmpfs);
    })
    (lib.mkIf (cfg.simple-disk.enable && cfg.simple-disk.systemd-boot.enable) {
      # EFI boot!
      boot.loader.systemd-boot.enable = lib.mkDefault true;
      boot.loader.systemd-boot.editor = false;
    })
    (lib.mkIf cfg.simple-disk.enable {
      assertions = [{
        assertion = builtins.stringLength cfg.simple-disk.device > 0;
        message = ''
          A device path must be provided for formatting to work!
          Set one at 'proesmans.filesystem.simple-disk.device'.
        '';
      }];

      disko.devices = {
        disk.disk1 = {
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
              root = {
                end = "-1G";
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
              encryptedSwap = {
                size = "100%";
                content = {
                  type = "swap";
                  randomEncryption = true;
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
    })
  ];
}
