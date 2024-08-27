{ lib, pkgs, config, ... }: {
  # Define the platform type of the target configuration
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;

  # Enables (nested) virtualization through hardware acceleration.
  # There is no harm in having both modules loaded at the same time, also no real overhead.
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = true;

  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  networking.hostId = "525346fb";
  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # ZFS pool, mostly default, for modern COW filesystem for local data.
  # Main use case is storing the nix store.
  disko.devices.zpool.zlocal = {
    type = "zpool";
    # ERROR; Intentionally left empty to not create a VDEV. No vdev explicitly creates
    # a non-redundant pool (aka RAID0)!
    mode = "";
    mountpoint = null;
    options = {
      # Set to 8KiB because of NVMe vdev members.
      ashift = "13";
      autotrim = "on";
    };
    # Configure the pool (aka pool-root aka dataset-parent) filesystem.
    # WARN; These settings are automatically inherited
    rootFsOptions = {
      # NOTE; No mounting/auto-mounting
      canmount = "off";
      # NOTE; Datasets do not inherit a parent mountpoint.
      mountpoint = "none"; # WARN; Dataset option for mountpoint must be set to `null`
      # NOTE; Opt out of built-in snapshotting, sanoid is used
      "com.sun:auto-snapshot" = "false";
    };
    datasets = {
      "root" = {
        # Root filesystem, a catch-all
        type = "zfs_fs";
        mountpoint = "/";
        postCreateHook = ''
          # Generate empty snapshot in preparation for impermanence
          zfs list -t snapshot -H -o name | grep -E '^zlocal/root@empty$' || zfs snapshot 'zlocal/root@empty'
        '';
        options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
      };
      #"persist" = {
      # In preparation for impermanence
      #};
      "persist/logs" = {
        # Stores systemd logs
        type = "zfs_fs";
        mountpoint = "/var/log";
        options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
      };
      # "persist/home" = {
      #   # User data
      #   type = "zfs_fs";
      #   # WARN; Potential race while mounting, see the note about zfs generators
      #   # REF; https://github.com/NixOS/nixpkgs/issues/212762
      #   mountpoint = "/home";
      #   # Workaround sync hang with SQLite WAL
      #   # REF; https://github.com/openzfs/zfs/issues/14290
      #   # See also `overlays.atuin`!
      #   # options.sync = "disabled";
      # };
      "nix" = {
        # Nix filestore, contains no state
        type = "zfs_fs";
        mountpoint = "/nix";
        options = {
          atime = "off"; # nix store doesn't use access time
          sync = "disabled"; # No sync writes
          # NOTE; The nix store is shared into virtual machines by virtiofs. Virtiofs requires 
          # the presence of acl metadata in our dataset
          # acltype = "off"; # set to off if there is no virtiofs in use
          acltype = "posixacl";
          xattr = "sa";
          mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
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
      "temporary" = {
        # Put /tmp on storage to save on RAM
        type = "zfs_fs";
        mountpoint = "/tmp";
        options = {
          compression = "lz4"; # High throughput lowest latency
          #sync = "disabled"; # No sync writes
          devices = "off"; # No mounting of devices
          setuid = "off"; # No hackery with user tokens on this filesystem
        };
      };
    };
  };

  # ZFS pool optimised for my spinning rust setup
  disko.devices.zpool.zstorage = {
    type = "zpool";
    mode = "raidz";
    mountpoint = null; # Don't (automatically) mount the pool filesystem
    postCreateHook = ''
      # Add SLOG device manually (not yet abstracted by DISKO)
      zpool add zstorage log '/dev/disk/by-partlabel/disk-slog-for-zstorage'
    '';
    # Configure the pool
    options = {
      # Set to 8KiB in preparation of NVMe vdev members. There is (also) no downside to making maximum write chunksize larger
      # than physical sector size.
      ashift = "13";
      autotrim = "on";
    };
    # Configure the pool (aka pool-root aka dataset-parent) filesystem.
    # WARN; Most of these settings are automatically inherited, check the documentation
    rootFsOptions = {
      # NOTE; No mounting/auto-mounting
      canmount = "off";
      # NOTE; Datasets do not inherit a parent mountpoint.
      # Default; Name of pool, 'zstorage' in this case
      mountpoint = "none"; # WARN; Dataset option for mountpoint must be set to `null`
      # NOTE; Fletcher is by far the fastest
      # Only change checksumming algorithm if dedup is a requirement, blake3 is a cryptographic
      # hasher for higher security on clash resistance
      checksum = "fletcher4";
      # NOTE; ZSTD-1 mode, performs better compression with ballpark same throughput of LZ4.
      # HELP; Doesn't require overwriting on sub-datasets
      compression = "zstd-fast-1";
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
      # NOTE; Make standard record size explicit
      # NOTE; Within hard disk pools it's better to go for bigger recordsizes to optimize away the static
      # seek time latency. But this improves the ratio of latency while increasing the average latency.
      # HELP; Change record size per dataset, there are various online sources with information
      # HELP; If application level caching is present, push the recordsize upwards
      recordsize = "128K";
      # NOTE; Compare filenames after normalizing using KC unicode conversion table. This turns characters into
      # equivalent characters; fullwidth "Ａ" (U+FF21) -> "A" (U+0041) [lossy conversion!!]
      normalization = "formKC";
      # NOTE; ZIL latency (duplicated) mode reduces pool fragmentation while burning through an (old) SSD SLOG device.
      # NOTE; ZIL blocks (aka the journal) are ephemeral, after the transaction commits they are erased. If those blocks were written
      # to the storage vdevs, this causes data holes of various sizes aka bad fragmentation.
      #
      # WARN; The ZIL is only used on synchronous writes (database storage, hypervisor I/O)! 
      # NOTE; For synchronous writes, continuous and/or random writes are collected into the ZIL until a continuous 
      # block of `recordsize` data is present. Then that data gets written to the storage vdevs on next commit.
      # The ZIL is part of the pool, but the amount of `recordsize` is taken from the target dataset configuration.
      # AKA; A bittorrent client might be performing small random writes accross the files until downloading completes, but the to-disk
      # behaviour of ZFS is not actually that small nor random! (Given there is no program repeatedly performing synchronous writes)
      #
      # WARN; Asynchronous writes follow the default path of being held in RAM and complete after being written to **storage vdev**.
      # WARN; You cannot directly improve performance of asynchronous writes (2024), but having an SLOG will free up disk IOPS by storing
      # synchronous write data outside the pool (onto the SLOG)!
      #
      # WARN; Not many applications perform a synchronous write by default.
      # HELP; You can *not* force a dataset to use the synchronous write-path to improve performance. AKA Setting `sync=always`
      # does not improve latency of asynchronous writes, but uses the ZIL to double-write data for replaying purposes 
      # after crash or power loss.
      #
      # - Bias ZIL on throughput -
      # When ZIL throughput (normal) mode writes records to the pool, data blocks are written to the storage vdevs. The data is then
      # 'already at the desired offset into the pool', and will not move anymore unless unlinked, and pointers to 
      # those locations are stored into the ZIL journal. To reiterate; The ZIL holds metadata, and data is already inside the storage vdev.
      # The effect being;
      #   - Less disk seeks and less -reads on asynchronous writes
      #       - Remember that synchronous writes are entirely written to ZIL first
      #   - Synchronous writes will take the performance hit of a fragmented pool, and during cleanup operations of the async writes
      #
      # - Bias ZIL on latency -
      # ZIL latency (duplicated) mode writes all data (up to size defined by zfs_immediate_write_sz) into the ZIL journal. This results
      # in writing data twice before it ends up at the storage vdev!
      # Latency is (supposed to be) lower because the write operation returns after persisting the journal, which is either 
      # on the storage vdevs or SLOG.
      # ZIL operations are a single threaded operation. Writting the ZIL to an SSD special device improves latency, but not necessary
      # throughput. For throughput a ZIL on pool often performs better.
      #
      # Optimizing the pool into a default mode and custom config for specific dataloads is hard, better is to simplify incorporating
      # the pool layout and physical device performance. Datasets should be designed to cluster related synchronous writes as much as possible.
      # My needs are very likely best served by the defaults, so try to keep configuration default as much as possible.
      #
      # My pool is a basic setup of RAIDZ1 HDD's and SLOG, where my burst traffic is less than 1 GiB of data, and average file size
      # should be >500 KiB. Except for database operations.
      #
      # So I configure ZIL bias on latency, and setup bias for throughput on datasets with bigger record size writes. The parameter
      # zfs_immediate_write_sz (transform a write from sync into async) only comes in effect when the SLOG drops out of the pool,
      # so not useful in the average case.
      # The SSD burn rate will be directly correlated to the write patterns on the (preferrably) few datasets that 
      # _are configured with latency bias_.
      #
      # HELP; Always use an SLOG, because the ZIL is always created and consequently stored on the storage vdevs (disks) without
      # pool-attached special device.
      # An indirect sync (happens on big file size writes), or setting logbias to throughput, will cause fragmentation 
      # between data and related metadata. A steady state pool will encounter double/triple read overhead 
      # due to this fragmentation. Consider burning away old SSD's for this purpose, only ~4GiB is necessary
      # and keep the rest overprovisioned. Erase first, use 'blkdiscard' to trim all sectors of the drive!
      #
      # HELP; Fun fact about SSD's; the total terabytes written (TBW) numbers assume the absolute worst environmental/binning cases.
      # If you have a reputable brand SSD, those things go into PETABYTES writes on lifetime! For any desktop use case (and as SLOG) you're
      # more likely to encounter a fried drive than hit the TBW limit in 20 years.
      # Pray for no firmware issues though! 🙏
      #
      # HELP; You'll notice that I haven't talked about mirroring devices into the SLOG. Because all data is always written to RAM, and
      # on synchronous writes copied into SLOG, I do need guarantees against the case when the system crashes together with an SSD failure.
      # A PSU failure could causes this effect, and that would also very likely fry my disks. I also do not have any more free SATA ports!
      # Combining this all leads me into "get a solid and tested backup solution", instead of trying to fix physical SLOG redundancy.
      #
      logbias = "latency";
      # NOTE; Enable record sizes larger than 128KiB
      "org.open-zfs:large_blocks" = "enabled";
      # NOTE; Opt out of built-in snapshotting, sanoid is used
      "com.sun:auto-snapshot" = "false";
    };
    # NOTE; You can create nested datasets without defining any parent. The parent datasets will exist ephemerally
    # and be automatically configured from the parent-parent dataset or pool-filesystem options.
    # Explicitly defining parent datasets becomes interesting to change a default option that will apply
    # automatically to all child datasets.
    #
    # ERROR; The following paths must exist before systemd is started!
    # pathsNeededForBoot = [ "/" "/nix" "/nix/store" "/var" "/var/log" "/var/lib" "/var/lib/nixos" "/etc" "/usr" ];
    # REF; https://github.com/linj-fork/nixpkgs/blob/master/nixos/lib/utils.nix#L13
    # The datasets that mount on those paths will be loaded during stage-1-boot under the zpool import action. The zpool import
    # happens before changing root, but ZFS is unaware of the soon-to-be root.
    # Nix automatically calculates the required mounts for the above paths, and will manually mount the datasets on the
    # soon-to-be root. An error will occur if that dataset was auto-mounted by pool import, so the datasets linked to any of the
    # above mountpoints needs option `mountpoint=legacy` to prevent this double-mount-error.
    # NOTE; "legacy" in NixOS means that the `filesystem.<mount-point>` option will (declaratively ofcourse) perform the mounting
    # at stage-1 boot. Any other option invokes on dynamic runtime behaviour, hence the error, and cannot be declaratively built upon.
    #
    # WARN; Switching root will unmount everything recursively and swap into the new root filesystem. That means the datasets
    # that were automounted are unmounted again. After systemd start, there is a single unit "zfs-mount.service" that remounts
    # those datasets.
    # If there are random boot failures, this could indicate a mount ordering issue in the context of systemd service units.
    # Systemd could be helpful and create paths for services, basically racing the zfs-mount service. The problem typically is
    # lack of ordering between units.
    # There is an upstream solution (i think, dunno what it exactly does) called ZFS automount generator (generators are a systemd
    # concept). This presumably solves shizzle? The ZFS automount generator script hasn't been turned into nixos options yet,
    # but it is accessible through the ZFS upstream package. So try it out, it will probably work because of the interlinking order
    # of dataset hierarchy.
    #
    datasets = {
      "vm" = {
        # Default storage location for vm state data without requirements.
        # HELP; Create sub datasets to specialize storage behaviour to the application.
        type = "zfs_fs";
        options = {
          canmount = "off";
          mountpoint = "/vm";
          # Qemu does its own application level caching
          # HELP; Set to none if you'd be storing raw- or qcow backed volumes.
          # NOTE; My virtual machines will run from a tmpfs by default!
          primarycache = "metadata";
          # Asynchronous IO for maximal volume performance
          logbias = "throughput";
          # Haven't done benchmarking to change away from the default
          recordsize = "128K";
          # ACL required for virtiofs
          acltype = "posixacl";
          xattr = "sa";
          # 
          devices = "off";
          setuid = "off";
        };
      };
      "vm/vault" = {
        # Basically file storage
        type = "zfs_fs";
        mountpoint = "/vm/vault";
      };
      "vm/vault/media" = {
        # Basically file storage
        type = "zfs_fs";
        mountpoint = "/vm/vault/media";
        options = {
          atime = "off";
          # WARN; A larger maximum recordsize needs to be weighted agains acceptable latency.
          # Back of enveloppe calculation; HDD seek time is ~10 ms, reading 16MB is ~130ms.
          # The record is split accross 2 disks (data + 1 parity) so each disk is held for
          # 75ms PER record. This literally kills our IOPS (cut by factor 7) in relation 
          # to 128kb (~11ms latency) on record miss.
          # NOW.. an average NAS diskstation will have 150-250 ms latency, so is 700% latency
          # difference _worst case_ really that bad?
          # HELP; To properly solve this I should build another pool for database storage
          # AKA all other storage types that won't be impacted by the higher latency.
          #
          # WARN; Records are processed in full, aka full 16M in RAM, full 16M checksummed.
          # A defect means the full 16MB must be resilvered.
          #
          # NOTE; ~45ms aka 20-25 IOPS seems like an OK(?) situation, also considering 
          # ARC prefetching is enabled and database caches should be in RAM.
          # HELP; HEAVILY VIRTUALIZE INTO RAM BOIISS
          recordsize = "8M";
          compression = "zstd-3";
          # TODO NFS mounting
          # TODO Sub layout
        };
      };
      # "vm/vault/torrent" = {};
      "vm/kanidm" = {
        # Kanidm state is basically an SQLite database. This dataset is tuned for that use case.
        type = "zfs_fs";
        options = {
          mountpoint = "/vm/kanidm"; # Default, but good to be explicit
          logbias = "latency";
          recordsize = "64K";
        };
      };
    };
  };
}