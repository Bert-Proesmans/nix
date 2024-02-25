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
    # TODO; Make disk device configurable
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.simple-disk.enable {
      disko.devices = {
        disk.disk1 = {
          device = "/dev/sda";
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
