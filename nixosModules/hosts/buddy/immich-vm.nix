{ lib, flake, profiles, meta-module, config, ... }:
{
  sops.secrets = {
    "immich-vm/ssh_host_ed25519_key" = {
      mode = "0400"; # Required by sshd
      restartUnits = [
        # New secrets are a new directory (new generation) and bind mount must be updated
        "shared-immich-seeds.mount"
        # New ssh key requires restart of guest
        "microvm@immich.service"
      ];
    };
  };

  # What's up with storage, really?
  #
  # TLDR; Mounting is literally passthrough, but there are two sides of the mount
  # story. To keep the host secured, and leaks through to the guest minimized, there
  # preparation on both sides of the mount is required.
  #
  # Deep dive; TODO

  # Immich database is Postgres
  # NOTE; Edit postgresql config, set 'full_page_writes = off'
  disko.devices.zpool.storage.datasets = {
    "postgres/state/immich" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/postgres/state/immich";
        acltype = "posixacl"; # Required by virtiofsd
        xattr = "sa"; # Required by virtiofsd
      };
    };
    "postgres/wal/immich" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/postgres/wal/immich";
        acltype = "posixacl"; # Required by virtiofsd
        xattr = "sa"; # Required by virtiofsd
      };
    };

    # HERE; Add more datasets for the guests
  };

  # Mounted at /shared/immich/<mount-name>
  proesmans.mount-central = {
    defaults.after-units = [ "zfs-mount.service" ];
    directories."immich".mounts = {
      "seeds".source = "/run/secrets/immich-vm";
      "state-postgresql".source = "/storage/postgres/state/immich";
      "wal-postgresql".source = "/storage/postgres/wal/immich";
    };
  };

  systemd.services."microvm-virtiofsd@immich".unitConfig = {
    RequiresMountsFor = config.proesmans.mount-central.directories."immich".bind-paths;
  };

  microvm.vms."immich" =
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
              source = "/shared/immich";
              mountPoint = "/data";
              tag = "state-immich";
              proto = "virtiofs";
            }
          ];
        };
      };
    };
}
