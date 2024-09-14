{ lib, flake, special, meta-module, config, ... }: {
  sops.secrets = {
    "photos-vm/ssh_host_ed25519_key" = {
      restartUnits = [
        # New ssh key requires restart of guest
        "microvm@photos.service"
      ];
    };
    "idm/openid-secret-immich" = { };
  };
  sops.templates."immich-config.json" = {
    file = ../photos/immich-config.json;
  };

  # What's up with storage, really?
  #
  # TLDR; Immich requires 4 directories that we're gonna split up in 
  #
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

    "media/pictures/immich" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/media/pictures/immich";
        acltype = "posixacl"; # Required by virtiofsd
        xattr = "sa"; # Required by virtiofsd
      };
    };

    "media/transcodes/immich" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/media/transcodes/immich";
        acltype = "posixacl"; # Required by virtiofsd
        xattr = "sa"; # Required by virtiofsd
      };
    };

    # HERE; Add more datasets for the guests
  };


  microvm.vms."photos" =
    let
      parent-hostname = config.networking.hostName;
      guest-ssh-key = config.sops.secrets."photos-vm/ssh_host_ed25519_key".path;
      immich-config-file = config.sops.templates."immich-config.json".path;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake special; };
      config = { config, special, ... }: {
        _file = ./photos-vm.nix;

        imports = [
          special.profiles.qemu-guest-vm
          (meta-module "photos")
          ../photos/configuration.nix # VM config
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

          microvm.volumes = [
            {
              # Persist tmp directory because of big downloads, video processing, and chunked uploads
              autoCreate = true;
              image = "/var/cache/microvm/photos/tmp-immich-disk.img";
              label = "tmp-immich";
              # NOTE; Sticky bit is automatically set
              mountPoint = "/var/tmp";
              size = 5 * 1024; # Megabytes
              fsType = "ext4";
            }
            {
              # Persist cache directory because machine learning
              autoCreate = true;
              image = "/var/cache/microvm/photos/cache-immich-disk.img";
              label = "cache-immich";
              mountPoint = "/var/cache";
              # TODO; Need to measure model sizes. Out of the box face and search models require ~1G
              size = 2 * 1024; # Megabytes
              fsType = "ext4";
            }
          ];

          microvm.central.shares = [
            {
              source = "/storage/postgres/state/immich";
              # NOTE; Not using the reference location because that one includes the postgres version
              # We want to have different version directories on the host.
              mountPoint = "/var/lib/postgresql";
              tag = "state-postgresql";
            }
            {
              source = "/storage/postgres/wal/immich";
              mountPoint = "/var/lib/wal-postgresql";
              tag = "wal-postgresql";
            }
            {
              source = "/storage/media/pictures/immich";
              mountPoint = config.services.immich.mediaLocation;
              tag = "library-immich";
            }
            {
              source = "/storage/storage/media/transcodes/immich";
              mountPoint = "/var/lib/transcodes-immich";
              tag = "transcodes-immich";
            }
          ];

          microvm.suitcase.secrets = {
            "ssh_host_ed25519_key".source = guest-ssh-key;
            "immich-config.json".source = immich-config-file;
          };

          services.openssh.hostKeys = [
            {
              path = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
              type = "ed25519";
            }
          ];
          systemd.services.sshd.unitConfig.ConditionPathExists = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
          systemd.services.sshd.serviceConfig.StandardOutput = "journal+console";
        };
      };
    };
}
