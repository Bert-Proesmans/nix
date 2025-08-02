{ ... }:
{
  boot.supportedFilesystems = [ "zfs" ]; # enables zfs
  # Do not force anything when pools have not been properly exported!
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;
  services.fstrim.enable = true;
  services.zfs.trim.enable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "weekly";

  # ZFS setup
  #
  # Rundown;
  #   - pool LOCAL, no mounting with datasets;
  #     - / (root)
  #     - /nix
  #     - /var/tmp (the disk-backed tmp)
  #     - /var/log
  #
  # Creates a RAIDZ0 pool from 1 partition.
  # The point is to have ZFS running for imperative dataset testing
  #
  disko.devices = {
    disk.root = {
      type = "disk";
      device = "/dev/sda";
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
            type = "BF01";
            name = "zfs_partition"; # Refer to this partition using '/dev/disk/by-partlabel/disk-root-zfs_partition'
            size = "100%";
            content = {
              type = "zfs";
              pool = "local"; # Must match disko.devices.zpool.<name>
            };
          };
        };
      };
    };

    zpool.local = {
      type = "zpool";
      # ERROR; Intentionally left empty to not create a VDEV. No vdev explicitly creates
      # a non-redundant pool (aka RAID0)!
      mode = "";
      options = {
        # Probably value '12', vhdx has sector size of 4KiB
        ashift = "0"; # Autodetect
        autotrim = "on";
      };
      # Configure the pool (aka pool-root aka dataset-parent) filesystem.
      # WARN; Some settings are _set once_, some are configurable per dataset
      rootFsOptions = {
        # NOTE; No mounting/auto-mounting
        canmount = "off";
        # NOTE; Datasets do not inherit a parent mountpoint.
        mountpoint = "none";
        compression = "lz4";
        # NOTE; Disable extended access control lists and use owner/group/other!
        # HELP; Set this parameter to `posixacl` when required, check documentation of your software!
        acltype = "off";
        # NOTE; Store file metadata as extensions in inode structure (for performance)
        xattr = "sa";
        # NOTE; Increase inode size, if ad-hoc necessary, from the default 512-byte
        dnodesize = "auto";
        # NOTE; Enable optimized access time writes
        # HELP; Disable access time selectively per dataset
        relatime = "on";
        # NOTE; Opt out of built-in snapshotting
        "com.sun:auto-snapshot" = "false";
      };

      datasets = {
        "root" = {
          # Root filesystem, a catch-all
          type = "zfs_fs";
          mountpoint = "/";
          postCreateHook = ''
            # Generate empty snapshot in preparation for impermanence
            zfs list -t snapshot -H -o name | grep -E '^local/root@empty$' || zfs snapshot 'local/root@empty'
          '';
          options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
          #
          options = {
            acltype = "posixacl";
          };
        };
        "nix" = {
          # Nix filestore, contains no state
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
          #
          options = {
            atime = "off"; # nix store doesn't use access time
            acltype = "posixacl"; # Required for virtio shares
          };
        };
        "nix/reserve" = {
          # Reserved space to allow copy-on-write deletes
          type = "zfs_fs";
          mountpoint = null;
          options = {
            canmount = "off";
            # Reserve disk space for files without incorporating snapshot and clone numbers.
            # WARN; Storage statistics are (almost) never straight up "this is the sum size of your data"
            # and incorporate reservations, snapshots, clones, metadata from self+child datasets.
            refreservation = "1G";
          };
        };
        "persist/logs" = {
          # Stores systemd logs
          type = "zfs_fs";
          mountpoint = "/var/log";
          options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
        };
        "temporary" = {
          # Put /var/tmp on a separate dataset to prevent DOS'ing the root dataset
          type = "zfs_fs";
          # NOTE; /var/tmp (and /tmp) are subject to automated cleanup
          mountpoint = "/var/tmp";
          options = {
            devices = "off"; # No mounting of devices
            setuid = "off"; # No hackery with user tokens on this filesystem
          };
        };
      };
    };
  };
}
