{ ... }:
{
  # Don't setup /tmp in RAM to make more of it available for software runtime
  fileSystems."/tmp" = {
    depends = [ "/var/tmp" ];
    device = "/var/tmp";
    fsType = "none";
    options = [
      "rw"
      "noexec"
      "nosuid"
      "nodev"
      "bind"
    ];
  };

  # NOTE; You can create nested datasets without explicitly defining any of the parents. The parent datasets will
  # be automatically created (as nomount?).
  disko.devices.zpool.storage.datasets = {
    "documents" = {
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

    "media" = {
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

    "postgres" = {
      # NOTE; Base dataset for storage data managed by a postgres database server.
      type = "zfs_fs";
      options = {
        canmount = "off";
        mountpoint = "none";
        atime = "off";

        # Performance notes for postgres itself;
        #   - Disable database checksumming
        #     - Checksumming is a necessity in HA clusters with timelines though (eg Patroni)
        #   - Disable full_page_writes

        # Postgres page size is fixed 8K (hardcoded). A bigger recordsize is more performant on reads, but not writes.
        # Latency of any read under 1MiB is dominated by disk seek time (~10ms), so the choice of recordsize
        # between 8K and 128K is basically meaningless (as long as it's a multiple of 8K).
        recordsize = "32K";
        # Assumes all postgres state fits in RAM, so no double caching of data files.
        # Caches metadata for lower latency retrieval of non-cached records.
        primarycache = "metadata";
        # No fragmented writes from ZIL to data pool
        logbias = "latency";
      };
    };

    # Datasets could also be defined where they're used!
    #
    # eg
    # "postgres/forgejo/state" = {
    #   type = "zfs_fs";
    #   options.mountpoint = "/var/lib/postgres";
    #   # options = {
    #   # Optional dataset configuration here
    #   # };
    # };

    "sqlite" = {
      # NOTE; Base dataset for storage data managed by a sqlite database program.
      type = "zfs_fs";
      options = {
        canmount = "off";
        mountpoint = "none";
        atime = "off";

        # Performance notes for sqlite itself;
        #   - Set page size to 64KiB
        # SEEALSO; dataset options for postgres

        recordsize = "64K";
        primarycache = "metadata";
        logbias = "latency";
      };
    };

    "qemu" = {
      # NOTE; Default storage location for vm state data without specific requirements.
      #
      # NOTE; Qemu does its own application level caching on backing volume (by default, option cache=writeback)
      # HELP; Create sub datasets to specialize storage behaviour to the application.
      type = "zfs_fs";
      options = {
        canmount = "off";
        mountpoint = "none";
        atime = "off";
        acltype = "off";

        # Haven't done benchmarking to change away from the default
        recordsize = "128K";
        # Don't cache metadata because I expect infrequent reads and large write streams.
        # HELP; Set to metadata if you're not storing raw- or qcow backed volumes, or use specific cache control.
        primarycache = "none";
        # Should compress really well
        compression = "zstd-5";
      };
    };

    "log" = {
      # NOTE; Separate dataset to prevent denial-of-service (DOS) through cache-writes, and making important log data
      # storage redundant.
      type = "zfs_fs";
      mountpoint = "/var/log";
      options.mountpoint = "legacy";
    };

    "backup" = {
      # NOTE; This is the backup landing spot!
      # TODO; Check if the target dataset needs to exist?
      type = "zfs_fs";
      mountpoint = null;
      options.canmount = "off";
      options.readonly = "on";
    };

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
  };
}
