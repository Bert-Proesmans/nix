{ lib, ... }: {
  boot.supportedFilesystems = [ "zfs" ];
  # NOTE; Don't pin the latest compatible linux kernel anymore. It can be dropped from the package index
  # at unexpected moments and cause kernel downgrade.
  # Leave the boot.kernelPackages options at default to use the long-term stable kernel. The LTS is practically
  # guaranteed to be compatible with the latest zfs release.
  # REMOVED; boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # Boot is both efi and bios compatible
  # TODO; Remove grub in favour of systemd if mirrored EFI boot install is available through SystemD (or something else)
  # TODO; Integrate lanzaboot to sign boot stubs for EFI secure boot
  # TODO; Integrate TPM measured boot to only release decryption keys on unchanged platform configuration registers (PCR)
  # TODO; Encrypt root and data block storage; luks/luks+zfs/zfs native
  #       Don't forget to enable aes acceleration modules
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    # Uses file name conventions instead of explicitly registering each EFI executable with the EFI firmware.
    efiInstallAsRemovable = true;
    # ERROR; Must set the devices array to empty because disko fills it in trying to be helpful.
    # Tree boot partitions are configured, these take priority over giving the disks over for automated GRUB install.
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

  # Do not force anything when pools have not been properly exported!
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # WARN; Pools that hold no datasets for booting aren't mounted at stage-1 and stage-2!
  boot.zfs.extraPools = [ "storage" ];

  services.fstrim.enable = true;
  services.zfs.trim.enable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "weekly";

  # @@ Disk rundown @@
  #   - Partitions, root disk***
  #     - / (root)
  #     - /nix
  #     - /tmp (bindmount) + /var/tmp (reduce RAM usage when storage is plenty)
  #   - ZFS pool STORAGE, combination of persistent data and cache
  #     - /persist
  #       - **
  #     - /var/cache
  #       - **
  #     - /var/log
  #
  # **ZFS datasets are optimized per application, but mounted into a straightforward file hierarchy. Examples of dataset 
  # specialisation are:
  #     - image/video
  #     - postgres
  #     - sqlite
  #     - etc
  #
  # **There is no benefit enabling ZFS on root for these use-cases.
  #
  #
  # @@ ZFS Pool @@
  # Creates a RAIDZ1 pool from 3 disks + 1 SLOG device.
  #
  # ZFS is given partitions instead of entire disks. There is nothing inherently wrong with that
  # approach, nothing will break.
  # The pool partitions all have a fixed size, to combat differences in raw storage capacity.
  # The ZFS storage partition sizes are set to 3722 Gibibyte (~=3.6 Tebibyte ~= 4.0 Terabyte).
  # That makes ~3 Gibibyte available for other purposes (boot/swap) and rounding errors.
  #
  # The remaining space is used for swap space.
  # Swap works in round robin, so each disk provides some amount of swap into the total swap pool.
  # Since swap usage should be minimal and disks cannot be extended it's fine to put the swap space at the
  # end of the disk (slowest latency).
  #
  # Partition alignment is no problem under the circumstances below. Optimal start- and end alignment are both
  # automatically calculated by the software (s)gdisk.
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
  # @@ ZFS Datasets @@
  # On top of the pool is a dataset structure based on snapshot and replication policies, performance, and security.
  # See disko.zpool.<pool name>.datasets.
  #
  # Pool "storage" is optimised for spinning hard drives, bulk storage.
  #
  #
  # @@ ZFS mountpoint "legacy" within NixOS @@
  # The paths below must be mounted to start NixOS. There is a bunch of integration work happening right now so the
  # timing moments of stage-1/stage-2 and 'before SystemD starts' are in flux. At runtime SystemD is currently not 
  # completely aware of the full mount hierarchy for ZFS.
  #
  # pathsNeededForBoot = [ "/" "/nix" "/nix/store" "/var" "/var/log" "/var/lib" "/var/lib/nixos" "/etc" "/usr" ];
  # REF; https://github.com/NixOS/nixpkgs/blob/f7c8b09122de4faf7324c34b8df7550dde6feac0/nixos/lib/utils.nix#L56
  #
  # The default system configuration will mount the above paths during stage-1 boot.
  # Stage-1 is driven by a shell script contained within the initial RAMdisk (initrd/initramfs), it takes the declarative
  # filesystem information to figure out what needs to be mounted and in which order.
  # Stage-1 prepares a new filesystem root to load stage-2, this requires recursively re-mounting from current root to the new one.
  # Stage-2 is then SystemD init, loaded from the mounted /nix/store, taking over boot until (and after) the ~interactive stage.
  #
  # Moving into each stage starts with re-mounting the root filesystem recursively (all submounts too). The unmounting/remounting
  # action, in combination the zfs driver trying to automatically mount datasets, is currently not completely path ordering aware
  # because two different systems race each other (and are not aware of each other). This leads to the following symptoms;
  #   - hidden submount of child dataset (filsystem directory is empty) because parent dataset mounts afterwards
  #   - parent dataset unmount fails because child dataset is mounted
  #   - dataset is already mounted
  #
  # To prevent double-mount-error and other mounting errors mentioned above, configure dataset "mountpoint" option to value "legacy".
  # This option prevents zfs from automatically mounting datasets, and gives full control back to the stage-1 boot script.
  #
  # @@ ZFS errors on datasets for booting without mountpoint "legacy" @@
  # The datasets that mount on one of the "pathsNeededForBoot" will be loaded during stage-1-boot. This is also the stage where
  # zpool import executes and automatically mounts its datasets on the current root (or through the SystemD unit "zfs-mount.service").
  # NixOS stage-1 automatically calculates the required mounts for the above paths, and will manually mount the datasets on the
  # soon-to-be switched into root.
  # An error will occur if that dataset was (already) auto-mounted by pool import on the current filesystem root.
  #
  # There is a (supposed) upstream solution called ZFS automount generator (like FSTAB mount generator). This would(?) solve 
  # the requirement for explicitly setting mountpoint "legacy" on declaratively defined filesystem datasets.
  # This generator creates dynamic SystemD unit files for each dataset, and explicitly controls mounting and mount ordering.
  # The ZFS automount generator script hasn't been turned into nixos options yet, but it is accessible through the ZFS upstream package.
  # REF; https://github.com/NixOS/nixpkgs/issues/62644 (I'm not sure if this is actually better than explicitly setting "legacy")
  #
  disko.devices = {
    disk.slog-one = {
      type = "disk";
      device = "/dev/disk/by-id/ata-M4-CT128M4SSD2_00000000114708FF549B";
      preCreateHook = ''
        if ! blkid "/dev/disk/by-id/ata-M4-CT128M4SSD2_00000000114708FF549B" >&2; then
          # If drive contents were discarded, mark all sectors on drive as discarded
          blkdiscard "/dev/disk/by-id/ata-M4-CT128M4SSD2_00000000114708FF549B"
        fi
      '';
      content = {
        type = "gpt";
        partitions = {
          zfs = {
            type = "BF01";
            size = "4G";
            content = {
              type = "zfs";
              pool = "storage";
            };
          };
        };
      };
    };
    disk.local-one = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-INTEL_SSDPEKKW256G7_BTPY64630GRV256D";
      preCreateHook = ''
        if ! blkid "/dev/disk/by-id/nvme-INTEL_SSDPEKKW256G7_BTPY64630GRV256D" >&2; then
          # If drive contents were discarded, mark all sectors on drive as discarded
          blkdiscard "/dev/disk/by-id/nvme-INTEL_SSDPEKKW256G7_BTPY64630GRV256D"
        fi
      '';
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
            };
          };

          var = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
              mountOptions = [ "rw" "noexec" "nosuid" "nodev" ];
            };
          };

          nix = {
            size = "100G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              # NOTE; Nix boot stages and daemon remount parts of this partition at runtime!
              mountOptions = [ "nosuid" "nodev" "noatime" ];
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
              mountOptions = [ "umask=0077" "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          zfs = {
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
              mountOptions = [ "umask=0077" "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          zfs = {
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
              mountOptions = [ "umask=0077" "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          zfs = {
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

    zpool.storage = {
      type = "zpool";
      mode.topology = {
        type = "topology";
        vdev = [{
          mode = "raidz"; # RAID5
          members = [
            "storage-one"
            "storage-two"
            "storage-three"
          ];
        }];
        log = [{
          members = [ "slog-one" ];
        }];
      };
      options = {
        # Set to 8KiB sector sizes in preparation of NVMe vdev members.
        # There is (also) no downside to making maximum write chunksize larger than physical sector size.
        ashift = "13";
        autotrim = "on";
      };
      rootFsOptions = {
        # WARN; Most of these settings are automatically inherited, check the documentation

        # NOTE; No mounting/auto-mounting
        canmount = "off";
        # NOTE; Datasets inherit parent mountpoint.
        # HELP; Set an explicit mountpoint on the leaf datasets!
        mountpoint = "none";
        # NOTE; Fletcher is by far the fastest
        # Only change checksumming algorithm if dedup is a requirement!
        # HELP; Set blake3 (cryptographic hasher) for better clash resistance and when deduplication is activated.
        checksum = "fletcher4";
        # NOTE; ZSTD-fast-1 (minus 1, aka faster) mode, performs better compression with ballpark same throughput of LZ4.
        # HELP; Doesn't require overwriting on sub-datasets unless for specific data optimization
        compression = "zstd-fast-1";
        # NOTE; Since the storage location is central, granular access must be given to each directory within. Also virtio shares
        # require ACL enabled so just enable ACL for the entire storage set.
        acltype = "posixacl";
        # NOTE; Store file metadata as extensions in inode structure (for performance)
        xattr = "sa";
        # NOTE; Increase inode size, if ad-hoc necessary, from the default 512-byte
        dnodesize = "auto";
        # NOTE; Enable optimized access time writes
        # HELP; Disable access time selectively per dataset
        relatime = "on";
        # NOTE; Make standard record size explicit
        # NOTE; Within hard disk pools it's better to go for bigger recordsizes to optimize away the static seek time latency. 
        # But this _only_ improves the ratio of latency to retrieval bandwidth while increasing the average latency.
        # HELP; Change record size per dataset, there are various online sources with information
        # HELP; If application level caching is present, increase the recordsize
        recordsize = "128K";
        # NOTE; Compare filenames after normalizing using KC unicode conversion table. This turns characters into
        # equivalent characters; fullwidth "Ａ" (U+FF21) -> "A" (U+0041) [lossy conversion!!]
        # HELP; Do not overwrite unless good reason to
        normalization = "formKC";
        # @@ ZIL @@
        # The "ZFS intent log"(ZIL) is storage space allocated for synchronous data writes (database writes or hypervisor I/O).
        # Under default configuration this storage space is located inside the data vdevs for persistence and redundancy reasons.
        # But the ZIL is _not_ restricted to a specific start and end sector, ZIL data is spread over the entire disk. These ZIL blocks
        # contain both application data and its metadata. This difference becomes important for choosing a value for 'logbias'.
        # When a synchronous application data write completes, or a continuous block of 'recordsize' is comitted, the ZIL data 
        # is copied (written a second time) to the data vdevs. This second write is to the "permanent location" of the data.
        # This second write happens on the next ZFS commit trigger and introduces write holes when the ZIL data is freed.
        #
        # @@ SLOG @@
        # A "secondary log"(SLOG) device can hold the ZIL outside of the data vdevs. This makes the SLOG a "special vdev".
        # THE SLOG IS NOT A CACHE! The SLOG is never read from, unless to recover from a crash. The SLOG exists to persist the intent log,
        # which is always A DUPLICATE copy from RAM.
        # The SLOG is a tool to balance and optimize durability, application write completion latency, and "input-/output operations"(IOPS)
        # of the data vdevs (entire pool actually, they aren't linked to individual data vdevs).
        #
        # Best practises dictate that the SLOG must be attached to a pool in a redundant setup (like mirror). A loss of 
        # a SLOG device results in data loss.
        # When the SLOG vdev dissapears, the pool will automatically fall back to a ZIL on data vdevs. This is very much not desired
        # because ZFS cannot defragment its data vdevs. (Rebalancing exists but requires vdev expansion to do well)
        #
        # Operations touching the ZIL are locked to a single-thread meaning read/writes are serialized. A single SLOG device could
        # lose on throughput in contrast to data vdevs containing multiple devices.
        # There is a balance to find between reducing latency while retaining throughput on synchronous writes.
        #
        # HELP; Use an SLOG if your pool;
        #   1. has low IOPS due to low IOPS per disk
        #   2. has long write latency due to mix of synchronous and asynchronous writes
        #     AKA struggles to maintain expected IOPS performance
        #
        # @@ Asynchronous writes @@
        # An application writing data to a zfs dataset through standard filesystem utilities will invoke an asynchronous data write.
        # Both application data and its metadata are held in RAM until the ZFS commit trigger, after which the data is persisted to
        # the data vdevs.
        # Asynchronous writes _will lose data_ when the host crashes!
        #
        # @@ Synchronous writes @@
        # Contrary to asynchronous writes, used when an application wants guarantees about the persistence of application data.
        # Database applications and hypervisors use synchronous filesystem methods for synchronous writes.
        # Next to holding data in RAM, the data is also written to the ZIL. This solves the downside of asynchronous writes, but
        # introduces higher data write latency because disks are always slower to respond than RAM!
        # Not many applications perform synchronous data writes, so the synchronous write performance impact could be small.
        #
        # @@ Practical effects of 'sync' @@
        # sync=disabled => never use ZIL. this option will effectively lie to your applications about data persistance.
        # HELP; Use when write latency is important, and host can not crash, and disks cannot fail
        #
        # sync=always => use ZIL for asynchronous writes too. this option forces ZFS to always utilize the ZIL, but write 
        # to the ZIL asynchronously. This is _not_ the same as the synchronous write procedure!
        # HELP; Use when you want to persist all data to ZIL and use it as a write-ahead log.
        #
        # @@ logbias set to 'latency' @@
        # When writing to the ZIL, application data records (up to size defined by zfs_immediate_write_sz) are written to
        # the ZIL. This results in the "double write" described above.
        # Write latency is supposed to be lower if you have a fast SLOG device, in contrast to long hard disk seek time.
        # HELP; Set to latency if you have a fast SLOG and low IOPS pool
        #
        # @@ logbias set to 'throughput' @@
        # When writing to the ZIL, application data is directly written into the data vdevs. This eliminates the mentioned
        # above "double writes" for the data blocks only, improving the data throughput the pool can handle.
        # HELP; Set to throughput if have a high IOPS pool or want to balance IOPS between SLOG and pool
        #
        # @@ Pool considerations in reality @@
        # The storage pool is a RAIDZ1 of hard disks. The burst traffic will max out at 1 GB of data per second, and
        # average file size is 1-2 MiB (range 3 KiB to 5 GiB).
        # Only database and virtualisation writes will matter for latency optimization, since the bigger writes will be asynchronous.
        #
        # @@ Decision @@
        # I chose to setup an SLOG (SATA SSD) and bias on latency, since SATA does 6GBps and any SSD has factor 1.000 IOPS available
        # in contrast to hard disk drives. This will eat through the SSD lifetime "quicker", but its lifetime is normally
        # expected to be in PetaBytes written. I'll consider SSD's disposable, I have many more older SSD's of lower capacity.
        #
        # The parameter zfs_immediate_write_sz (transform a write from sync into async) only comes in effect when the SLOG
        # drops out of the pool, so not useful under normal circumstances. It could optimize towards bigger write holes and retaining
        # alignment, but probably best to keep it at default.
        #
        # HELP; Consider using an SLOG to keep ZIL from fragmenting your data vdevs.
        # An indirect sync (happens on big file size writes), or setting logbias to throughput, will cause fragmentation between data 
        # and related metadata. A steady state pool will encounter double/triple read overhead due to this fragmentation.
        # Consider burning away old SSD's for this purpose, only ~4GiB is necessary and keep the rest overprovisioned. Erase first;
        # use 'blkdiscard' to trim all sectors of the SSD before reinitializing into ZFS!
        #
        # HELP; Fun fact about SSD's; the total terabytes written (TBW) numbers assume the absolute worst environmental/binning cases.
        # If you have a reputable brand SSD, those things go into PETABYTES writes on lifetime! For any desktop use case (and as SLOG) you're
        # more likely to encounter a fried drive than hit the TBW limit in 20 years.
        # Pray for no firmware issues though! 🙏
        #
        logbias = "latency";
        # NOTE; Enable record sizes larger than 128KiB
        "org.open-zfs:large_blocks" = "enabled";
        # NOTE; Opt out of built-in snapshotting, sanoid is used
        "com.sun:auto-snapshot" = "false";
        #
        # Restrict privilege elevation in both directions of host<->guest through file sharing.
        devices = "off";
        setuid = "off";
        exec = "off";
      };

      # Datasets are filesystems, those are defined in ./filesystems.nix for readability.
      datasets = { };
    };
  };

  # Tune ZFS
  #
  # NOTE; This configuration is _not_ tackling limited free space performance impact.
  # Due to the usage of AVL trees to track free space, a highly fragmented or otherwise a full pool results in
  # more overhead to find free space. There is actually no robust solution for this problem, there is 
  # no quick or slow fix (defragmentation) at this moment in time.
  # ZFS pools should be physically sized at maximum required storage +- ~10% from the beginning.
  # * If your pool is full => expand it by a large amount.
  # * If your pool is fragmented => create a new dataset and move your data out of the old dataset + 
  # purge old dataset + move back into the new dataset.
  #
  # HELP; A way to solve used space performance impact is to set dataset quota's to limit space usage to ~90%.
  # With a 90% usage limit there is backpressure to cleanup earlier snapshots. Doesn't work if your pool is
  # full though, only increasing raw storage space will!
  boot.extraModprobeConfig = ''
    # Fix the commit timeout (seconds), because the default has changed before
    options zfs zfs_txg_timeout=5

    # This is a hypervisor server, and ZFS ARC is sometimes slow with giving back RAM.
    # It defaults to 50% of total RAM, but we fix the amount.
    # 8 GiB (bytes)
    options zfs zfs_arc_max=8589934592

    # Data writes less than this amount (bytes) are written in sync, while writes larger are written async.
    # WARN; Only has effect when no SLOG special device is attached to the pool to be written to.
    #
    # ERROR; Data writes larger than the recordsize are automatically async, to prevent complexities while handling
    # multiple block pointers in a ZIL log record.
    # HELP; Set this value equal to or less than the largest recordsize written on this system/pool.
    # 1MiB (bytes?)
    options zfs zfs_immediate_write_sz=1048576

    # Disable prefetcher. Zfs could proactively read data expecting inflight, or future requests, into the ARC.
    # We have a system with pools on low IOPS hard drives, including high random access load from databases.
    # I choose to not introduce additional I/O latency when the potential for random access is high!
    #
    # HELP; Re-enable prefetch on system with fast pools (like full ssd-array)
    options zfs zfs_prefetch_disable=1
  '';
}
