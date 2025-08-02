{
  lib,
  flake,
  special,
  meta-module,
  config,
  ...
}:
{
  disko.devices.zpool.storage.datasets = {
    "postgres/state/test" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/postgres/state/test";
        acltype = "posixacl";
        xattr = "sa";
      };
    };
  };

  systemd.tmpfiles.settings."20-test-mounts" = {
    "/shared/test".d = {
      user = "root";
      group = "root";
      # WARN; The directory itself is a writeable mount, so these permissions could change!
      # The guest should update these permissions as seen fit.
      mode = "0755";
    };

    # HERE; Add more datasets to prepare a shared folder for
  };

  microvm.vms.test =
    let
      parent-hostname = config.networking.hostName;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake special; };
      config =
        { lib, ... }:
        {
          _file = ./test-vm.nix;

          imports = [
            special.profiles.qemu-guest-vm
            (meta-module "test")
          ];

          config = {
            nixpkgs.hostPlatform = lib.systems.examples.gnu64;
            microvm.vsock.cid = 666;

            proesmans.facts.tags = [ "virtual-machine" ];
            proesmans.facts.meta.parent = parent-hostname;

            microvm.shares = [
              {
                source = "/storage/postgres/state/test";
                #source = "/shared/test";
                #mountPoint = "/persist/data";
                mountPoint = "/data";
                tag = "state";
                proto = "virtiofs";
              }
            ];

            system.stateVersion = "24.05";
          };
        };
    };
}
