{ ... }:
{
  # NOTE; You can create nested datasets without explicitly defining any of the parents. The parent datasets will
  # be automatically created (as nomount?).
  disko.devices.zpool.zroot.datasets = {
    "maintenance" = {
      # Reserved space to allow copy-on-write deletes.
      # WARN; When the storage is full-full it's impossible to impose new limits because every property write is written to the pool.
      # Empty space is necessary to delete files too!
      type = "zfs_fs";
      mountpoint = null;
      options = {
        canmount = "off";
        # Reserve disk space (without counting sub-datasets; snapshots, clones, child datasets).
        # WARN; Storage statistics are (almost) never straight up "this is the sum size of your data"
        # and incorporate reservations, snapshots, clones, metadata from self+child datasets.
        refreservation = "1G";
      };
    };

    # ALWAYS BACKUP THE ENCRYPTIONROOT! At least once after updating key material.
    # REF; https://sambowman.tech/blog/posts/mind-the-encryptionroot-how-to-save-your-data-when-zfs-loses-its-mind/
    #
    # NOTE; Stage-1 force loads encryption keys for _all_ encryption roots during pool import. It's not possible to use one
    # dataset as an unlock medium for another dataset because the filesystem is not mounted inbetween loading encryption keys.
    "encryptionroot" = {
      # Encryptionroot for the root filesystem, basically everything local to the system unimportant to backup.
      type = "zfs_fs";
      options = {
        mountpoint = "none";
        canmount = "off";
        encryption = "aes-256-gcm";
        keyformat = "passphrase";
        # Generate and store a new key using;
        # tr -dc '[:alnum:]' </dev/urandom | head -c64
        #
        # WARN; Path hardcoded in tasks.py !
        # keylocation = "file:///tmp/deployment-disk.key"; # Path only used when formatting !
        keylocation = "prompt";
        pbkdf2iters = "500000";
      };
      postCreateHook = ''
        # zfs set keylocation="<url[http://|file://]>" "<fully qualified dataset path>"
        zfs set keylocation="prompt" "zroot/encryptionroot"
      '';
    };

    "encryptionroot/root" = {
      type = "zfs_fs";
      options.mountpoint = "legacy";
      mountpoint = "/";
      mountOptions = [ "defaults" ];
    };

    "encryptionroot/nix" = {
      type = "zfs_fs";
      options = {
        mountpoint = "legacy";
        acltype = "off";
        atime = "off";
        relatime = "off";
        # ERROR; Disko create/mount uses ZFS dataset properties while booting nix uses filesystem mount options
        #
        # ERROR; During deploy the error below pops up;
        #        error: executing '/nix/store/<hash>-bash-5.3p3/bin/bash': Permission denied
        # Permission denied because noexec is enabled on the mount!
        # The workaround is to re-enable exec on this dataset
        exec = "on";
      };
      mountpoint = "/nix";
      mountOptions = [
        "nosuid"
        "nodev"
        "noatime"
      ];
    };

    "encryptionroot/log" = {
      # NOTE; Separate dataset to prevent denial-of-service (DOS) through cache-writes, and making important log data
      # storage redundant.
      type = "zfs_fs";
      options = {
        mountpoint = "legacy";
        # Should compress really well
        compression = "zstd-5";
      };
      mountpoint = "/var/log";
    };

    "encryptionroot/documents" = {
      # NOTE; Base dataset for computer backups, generally documents and various forms of important stuff.
      type = "zfs_fs";
      options = {
        canmount = "off";
        mountpoint = "none";
        recordsize = "128k"; # Default
        # Should compress really well
        compression = "zstd-5";
      };
    };

    "encryptionroot/media" = {
      # NOTE; Base dataset for multimedia files.
      type = "zfs_fs";
      options = {
        canmount = "off";
        mountpoint = "none";
        # WARN; A larger maximum recordsize needs to be weighted agains acceptable latency.
        # Back of enveloppe calculation for recordzise 16MiB;
        #   - HDD seek time is ~10 ms, reading 16MiB is ~130ms.
        #   - Records are split accross 2 disks (data + 1 parity (RAIDZ1)).
        # => Each disk is held for 75ms PER record.
        # This literally kills our IOPS (cut by factor 7) in contrast to 128kb (~11ms latency) on record miss.
        # NOW.. an average NAS diskstation will have 150-250 ms latency, so is 700% latency difference _worst case_ really that bad?
        #
        # NOTE; Records are processed in full, aka full 16M in RAM, full 16M checksummed. A defect means a record is defected,
        # meaning the full 16MB must be recovered/resilvered.
        #
        # NOTE; ~45ms for 10MiB aka 20-25 IOPS seems like an OK(?) situation. Thats (rounded up) about 25 media items loaded from the pool
        # per second, or 10 media items per 400ms (target response latency of internet request).
        # Pictures are smaller than 10MiB, up to a third, so the picture count is up to 3 times larger.
        #
        # HELP; Perform application caching as much as possible (AKA heavily virtualize into RAM).
        # HELP; Lower the recordsize for latency, increase the recordsize for increased compression ratio.
        #
        # ERROR; recordsize must be power of 2 between 512B and 16M => It's not possible to pick 10, must be 8M or 16M!
        recordsize = "8M"; # == Maximum recordsize
        # NOTE; Media is generally incompressible, ZFS will use lz4 to test data compressability and early return the compression path
        # if not or low compressible. Since this is dormant storage any gains on sidecar data are a nice plus.
        # NOTE; The hyphen is confusing with negative levels so these are denoted as zstd-fast-N.
        compression = "zstd-3";
      };
    };

    # Datasets could also be defined where they're used!
    #
    # eg
    # "media/immich/pictures" = {
    #   type = "zfs_fs";
    #   options.mountpoint = "/var/lib/immich";
    #   #   # options = {
    #   # Optional dataset configuration here
    #   # };
    # };
  };
}
