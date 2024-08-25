{ lib, pkgs, config, ... }: {

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

  # ZFS setup
  #
  # Rundown;
  #   - pool ZLOCAL, mounted at null
  #     - /nix
  #     - /tmp -> trades lower memory usage for storage
  #   - pool ZSTORAGE, mounted at 
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
              pool = "zlocal";
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
              pool = "zstorage";
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
              pool = "zstorage";
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
              pool = "zstorage";
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
}
