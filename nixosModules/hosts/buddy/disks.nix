{ lib, ... }: {

  # this is both efi and bios compatible
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    # Uses convention instead of explicitness between EFI firmware and this operating system.
    efiInstallAsRemovable = true;
    # WARN; Something (disko?) adds devices to this array. We're using multiple boot partitions, defined
    # below, which get accumulated into effectively installing grub twice on each disk.
    # These devices are forced empty so the grub install won't produce warnings/errors.
    devices = lib.mkForce [ ];
    mirroredBoots = [
      {
        devices = [ "nodev" ];
        path = "/boot/0";
      }
      {
        devices = [ "nodev" ];
        path = "/boot/1";
      }
      {
        devices = [ "nodev" ];
        path = "/boot/2";
      }
    ];
  };

  systemd.tmpfiles.settings."1-base-datasets" = {
    # Assumes ZFS datasets will be mounted on paths /storage/**/X
    # The parent folder permissions are explicitly set to prevent accidental
    # world access.
    "/storage".d = {
      user = "root";
      group = "root";
      mode = "0700";
    };
  };

  # Do not force anything when pools have not been properly exported!
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;
  # WARN; We have a zpool defined for pure data.
  # A pure data zpool is when all ..zpool.<name>.datasets.<name> are not needed for boot
  #   => Imported pool is a requirement for the dataset mount
  #     => But no dataset of the pool requires mounting, so the pool doesn't import
  #   => disko does not add additional pools to the option boot.zfs.extraPools
  #
  # NOTE; The pool is imported in stage-2 (after initrd finished switching root). The unit ordering
  # is before sysinit.target. Search the system logs for "Starting Import ZFS pool" to imperatively
  # answer ordering questions.
  boot.zfs.extraPools = [ "storage" ];

  # Tune ZFS
  #
  # NOTE; Not tackling limited free space performance impact. Due to the usage of AVL trees to track free space,
  # a highly fragmented or simply a full pool results in more overhead to find free space. There is actually no
  # robust solution for this problem, there is no quick or slow fix (defragmentation). Your pool should be sized
  # at maximum required space +- ~10% from the beginning.
  # If your pool is full => expand it by a large amount. If your pool is fragmented => create a new dataset and
  # move your data out of the old dataset + purge old dataset + move back into the new dataset.
  #
  # HELP; A way to solve used space performance impact is to set dataset quota's to limit space usage to ~90%.
  # With a 90% usage limit there is backpressure to cleanup earlier snapshots. Doesn't work if your pool is
  # full though!
  boot.extraModprobeConfig = ''
    # Fix the commit timeout (seconds), because the default has changed before
    options zfs zfs_txg_timeout=5

    # This is a hypervisor server, and ZFS ARC is sometimes slow with giving back RAM.
    # It defaults to 50% of total RAM, but we fix it to 8 GiB (bytes)
    options zfs zfs_arc_max=8589934592

    # Data writes less than this amount (bytes) are written in sync, while writes larger are written async.
    # WARN; Only has effect when no SLOG special device is attached to the pool to be written to.
    #
    # ERROR; Data writes larger than the recordsize are automatically async, to prevent complexities while handling
    # multiple block pointers in a ZIL log record.
    # Set this value equal to or less than the largest recordsize written on this system/pool. (bytes?)
    options zfs zfs_immediate_write_sz=1048576

    # Disable prefetcher. Zfs could proactively read data expecting inflight or future requests, into the ARC.
    # We have a system with pools on (low IOPS) hard drives, including high random access load of databases.
    # It's best to not introduce additional I/O latency when the potential for random access is high!
    #
    # NOTE; No-brainer on full ssd array though.. one day
    options zfs zfs_prefetch_disable=1
  '';

  services.fstrim.enable = true;
  services.zfs.trim.enable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "weekly";

  # ZFS setup
  #
  # Rundown;
  #   - pool LOCAL, mounted at null
  #     - /
  #     - /nix
  #     - /tmp -> trades lower memory usage for storage
  #   - pool STORAGE, mounted at null
  #     - 
  #
  # Creates a RAIDZ1 pool from 3 disks + 1 SLOG device.
  # The pool partitions are aligned and all have a fixed size, the remaining size is kept for swap space.
  # Swap can work in round robin, so each disk provides some amount of swap into the total swap pool.
  #
  # On top of the pools is a dataset buildout for data handling, a mix of snapshot and replication
  # policies, performance, and security go into the design.
  #
  # The ZFS storage partition sizes are set to 3722 Gibibyte (~=3.6 Tebibyte ~= 4.0 Terabyte).
  # That makes ~3 Gibibyte available for other purposes (boot/swap) and rounding errors.
  #
  # ZFS is given partitions instead of entire disks. There is nothing inherently wrong with that
  # approach, nothing will break.
  #
  # Partition alignment is no problem under the circumstances below. Both start- and end alignment is
  # provided by the software (s)gdisk.
  # - sgdisk tries to align by default on 2048 * sectors (aka flash/data pages), assuming 512-byte sectors
  #   means 1 mebibyte
  #   - if the disk reports bigger sector sizes, the 2048 sector alignment is recalculated to
  #     a multiple of 8 sectors with target around 1 mebibyte
  #
  # Basically, don't worry about it if you DO all of the following;
  #   - don't calculate in sectors manually
  #   - don't work with sizes less than 1 mebibyte
  #
  # If the disks, anno 2024, do not contain 4096-byte sectors they will contain 8192-byte pages. 1 mebibyte is
  # a multiple of both 4096 and 8192 bytes, which means going for 8192 alignment (ashift=13) will not
  # introduce performance issues due to page misalignment.
  # There is no performance loss because the sector sizes are used as a unit of contiguous writes. The reverse,
  # smaller contiguous writes than physical sectors, will induce a performance penalty because of the
  # copy+update+overwrite cycle _per write_.
  #
  # These are the considerations for running ZFS on partitionss;
  # - Disk access is shared between ZFS and other processes using the same disk. ZFS will be unaware of
  #   the other software accessing the disk, and cannot be made aware of this happening.
  # - The kernel performs (fairness) access scheduling for each disk. When giving disks to ZFS
  #   it automatically disables this I/O scheduler. Disable this manually for a bit of latency
  #   improvement.
  #
  # With the consideration that every disk is either an SSD/NVME or managed through ZFS it's
  # better to disable the scheduler by default for all disks ({ boot.kernelParams = [ "elevator=none" ]; }).
  # Manually enable the scheduler again per-disk that requires it.
  # HELP; Since 23.11, NixOS includes the necessary UDEV rules to disable the I/O scheduler when ZFS device/partition
  # is found.
  disko.devices = {
    disk.slog = {
      type = "disk";
      device = "/dev/disk/by-id/ata-M4-CT128M4SSD2_00000000114708FF549B";
      content = {
        type = "gpt";
        partitions = {
          slog = {
            size = "4G";
            name = "for-zstorage"; # Refer to this partition using '/dev/disk/by-partlabel/disk-slog-for-zstorage'
          };
        };
      };
    };
    disk.local-one = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-INTEL_SSDPEKKW256G7_BTPY64630GRV256D";
      content = {
        type = "gpt";
        partitions = {
          one = {
            type = "BF01";
            size = "200G";
            content = {
              type = "zfs";
              pool = "local";
            };
          };
        };
      };
    };
    # Using `boot.loader.grub.mirroredBoots` (GRUB bootloader) to keep the boot data in sync accross disks.
    # I much prefer the clean presentation of systemd-boot, compared to grub, though ..
    disk.storage-one = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD40EFPX-68C6CN0_WD-WX22D93FVL17";
      content = {
        type = "gpt";
        partitions = {
          # for grub MBR
          boot = {
            type = "EF02";
            size = "1M";
          };
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/0"; # WARN; Unique per disk!
              mountOptions = [ "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          root = {
            type = "BF01";
            size = "3722G";
            content = {
              type = "zfs";
              pool = "storage";
            };
          };
          #
          swap = {
            size = "100%";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
        };
      };
    };
    disk.storage-two = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3VE4XDK";
      content = {
        type = "gpt";
        partitions = {
          # for grub MBR
          boot = {
            type = "EF02";
            size = "1M";
          };
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/1"; # WARN; Unique per disk!
              mountOptions = [ "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          root = {
            type = "BF01";
            size = "3722G";
            content = {
              type = "zfs";
              pool = "storage";
            };
          };
          #
          swap = {
            size = "100%";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
        };
      };
    };
    disk.storage-three = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0EYF88K";
      content = {
        type = "gpt";
        partitions = {
          # for grub MBR
          boot = {
            type = "EF02";
            size = "1M";
          };
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/2"; # WARN; Unique per disk!
              mountOptions = [ "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          root = {
            type = "BF01";
            size = "3722G";
            content = {
              type = "zfs";
              pool = "storage";
            };
          };
          #
          swap = {
            size = "100%";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
        };
      };
    };
  };

  # ZFS pool, mostly default, for modern COW filesystem for local data.
  # Main use case is storing the nix store.
  disko.devices.zpool.local = {
    type = "zpool";
    # ERROR; Intentionally left empty to not create a VDEV. No vdev explicitly creates
    # a non-redundant pool (aka RAID0)!
    mode = "";
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
      # NOTE; Opt out of built-in snapshotting, sanoid is used
      "com.sun:auto-snapshot" = "false";
    };

    # Datasets are defined where they're used!
    # SEEALSO; ./hardware-configuration.nix
    # datasets = {};
  };

  # ZFS pool optimised for my spinning rust setup
  disko.devices.zpool.storage = {
    type = "zpool";
    mode = "raidz";
    postCreateHook =
      let
        label-zpool = "storage";
        device-node = "/dev/disk/by-partlabel/disk-slog-for-zstorage";
      in
      ''
        # Add SLOG device manually (not yet abstracted by DISKO).
        # Target device node is matched as zfs member, and matching zpool label.
        #
        # NOTE; lsblk outputs something like below when the slog is attached
        # /dev/<moniker> zfs_member  storage
        #
        # ERROR; This lacks pool ID matching! But we're assuming the pools are always destroyed
        # together with disk contents between script runs, nor do we expect the drives to move
        # between systems (that happen to have the same pool labels) without a full wipe.
        #
        # ERROR; This also doesn't check the current pool state, where an SLOG could have been detached
        # but that doesn't automatically destroy the partition data on-disk!
        #
        if lsblk -o FSTYPE,LABEL ${device-node} --noheadings | grep -q "^zfs_member\s\+${label-zpool}\$"; then
          echo "Not attaching SLOG device to pool ${label-zpool} because it already belongs to a pool with the same name."
        else
          if ! zpool add ${label-zpool} log ${device-node}; then
            echo "Failed to attach SLOG device '${device-node}' for ${label-zpool}." >&2
          fi
        fi
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
      # NOTE; Datasets inherit a parent's mountpoint.
      mountpoint = "/storage";
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
      #
      # Guest sharing security, restrict privilege elevation in both directions of host<->guest.
      devices = "off";
      setuid = "off";
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
      "volumes" = {
        # Default storage location for vm state data without requirements.
        # HELP; Create sub datasets to specialize storage behaviour to the application.
        type = "zfs_fs";
        options = {
          mountpoint = "/var/cache/microvm";
          # Qemu does its own application level caching
          # HELP; Set to none if you'd be storing raw- or qcow backed volumes.
          # NOTE; My virtual machines will run from a tmpfs by default!
          primarycache = "metadata";
          # Asynchronous IO for maximal volume performance
          logbias = "throughput";
          # Haven't done benchmarking to change away from the default
          recordsize = "128K";
          # Don't store access times
          atime = "off";
        };
      };
      "media" = {
        type = "zfs_fs";
        options = {
          canmount = "off";
          # ACL required for virtiofs
          acltype = "posixacl";
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
          recordsize = "1M";
          compression = "zstd-3";
        };
      };
      "media/pictures" = {
        type = "zfs_fs";
        options = {
          mountpoint = "/storage/media/pictures";
        };
      };
      "media/video" = {
        type = "zfs_fs";
        options = {
          mountpoint = "/storage/media/video";
          # SEEALSO; recordsize comment on dataset media
          recordsize = "8M";
        };
      };
      "media/transcodes" = {
        type = "zfs_fs";
        options = {
          mountpoint = "/storage/media/transcodes";
        };
      };
      "postgres" = {
        type = "zfs_fs";
        options = {
          canmount = "off";
          # ACL required for virtiofs
          acltype = "posixacl";
          atime = "off";

          # Performance notes;
          #   - Disable database checksumming
          #     - Checksumming is a necessity in HA clusters with timelines though (eg Patroni)

          # Postgres page size is fixed 8K. A bigger recordsize is more performant on reads, but not writes.
          recordsize = "32K";
          # Assumes all postgres state fits in RAM, so no double caching of data files
          primarycache = "metadata";
          # No fragmented writes from ZIL to data pool
          logbias = "latency";
        };
      };
      "postgres/state" = {
        # NOTE; Inherit from this dataset!
        type = "zfs_fs";
        options = {
          canmount = "off";
          mountpoint = "/storage/postgres/state";
        };
      };
      "postgres/wal" = {
        # NOTE; Inherit from this dataset!
        type = "zfs_fs";
        options = {
          canmount = "off";
          mountpoint = "/storage/postgres/wal";
        };
      };
      "sqlite" = {
        type = "zfs_fs";
        options = {
          canmount = "off";
          # ACL required for virtiofs
          acltype = "posixacl";
          atime = "off";
          # SEEALSO; dataset options for postgres
          recordsize = "64K";
          primarycache = "metadata";
          logbias = "latency";
        };
      };
      "sqlite/state" = {
        # NOTE; Inherit from this dataset!
        # WARN; SQLite page size can and should be set to 64K
        type = "zfs_fs";
        options = {
          canmount = "off";
          mountpoint = "/storage/sqlite/state";
        };
      };

      # Datasets are defined where they're used!
      # SEEALSO; XX-vm.nix
      # datasets = {};
    };
  };
}
