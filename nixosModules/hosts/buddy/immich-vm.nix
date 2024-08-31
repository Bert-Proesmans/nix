{ lib, flake, profiles, meta-module, config, ... }:
let
  # ERROR; Postgres major versions require manual upgrades! To not shoot myself into the foot
  # I prepare multiple datasets on the host to not accidentally clobber data, plus the second
  # dataset location makes upgrading the database files easier by not requiring to do the process
  # inplace!
  #
  # NOTE; Yes, that's double config, because the first is a microvm option and the second
  # is the module evaluation!
  version-pg = config.microvm.vms.immich.config.config.services.postgresql.package.psqlSchema;
in
{
  sops.secrets."immich-vm/ssh_host_ed25519_key" = {
    # For virtio ssh
    mode = "0400";
    restartUnits = [ "microvm@immich.service" ]; # Systemd interpolated service
  };

  # Immich database is Postgres
  disko.devices.zpool.zstorage.datasets = {
    # NOTE; Edit postgresql config, set 'full_page_writes = off'
    "vm/immich/db/state" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/vm/immich/db/${version-pg}/state"; # Default, but good to be explicit
        logbias = "latency";
        recordsize = "64K";
      };
    };
    "vm/immich/db/wal" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/vm/immich/db/${version-pg}/wal"; # Default, but good to be explicit
        logbias = "latency";
        recordsize = "64K";
      };
    };
  };

  microvm.vms.immich =
    let
      parent-hostname = config.networking.hostName;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake profiles; };
      config = { profiles, ... }: {
        _file = ./immich-vm.nix;

        imports = [
          profiles.qemu-guest-vm
          (meta-module "immich")
          ../photos.nix # VM config
        ];

        config = {
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;
          microvm.vcpu = 2;
          microvm.mem = 4096; # MB
          microvm.vsock.cid = 42;

          proesmans.facts.tags = [ "virtual-machine" ];
          proesmans.facts.meta.parent = parent-hostname;

          microvm.interfaces = [{
            type = "macvtap";
            macvtap = {
              # Private allows the VMs to only talk to the network, no host interaction.
              # That's OK because we use VSOCK to communicate between host<->guest!
              mode = "private";
              link = "main";
            };
            id = "vmac-immich";
            mac = "42:de:e5:ce:a8:d6"; # randomly generated
          }];

          microvm.shares = [
            {
              source = "/run/secrets/immich-vm"; # RAMFS coming from sops
              mountPoint = "/seeds";
              tag = "secret-seeds";
              proto = "virtiofs";
            }
            {
              source = "/vm/immich/db/${version-pg}";
              mountPoint = "/data/db";
              tag = "state-db-immich";
              proto = "virtiofs";
            }
          ];
        };
      };
    };
}
