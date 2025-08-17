{ ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda"; # OCI SSD IOPS, HDD throughput (24 MB/s)
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          # NOTE; LUKS container
          #     => contains Pyhysical Volume (PV [LVM])
          #       => contains Volume Group (VG [LVM])
          #         => contains logical volume/raw block device for swap writeback
          #         => contains logical volume/ext4 filesystem for root filesystem
          luks = {
            size = "100%";
            content = {
              type = "luks";
              # Refer to this virtual block device by "/dev/mapper/crypted".
              # Partitions within are named "/dev/mapper/cryptedN" with N being 1-indexed partition counter
              name = "crypted";
              extraFormatArgs = [
                "--type luks2"
                "--hash sha256"
                "--pbkdf argon2i"
                "--iter-time 10000" # 10 seconds before key-unlock
                # Best performance according to cryptsetup benchmark
                "--cipher aes-xts-plain64" # [cipher]-[mode]-[iv] format
                # NOTE; I'm considering AES-128 (~126 bit randomness) secure with global (world) hashrate being less than
                # 2^81 hashes per second.
                "--key-size 256" # SPLITS IN TWO (xts) !!
                "--use-urandom"
              ];
              # Generate and store a new key using;
              # tr -dc '[:alnum:]' </dev/urandom | head -c64
              #
              # WARN; Path hardcoded in tasks.py !
              passwordFile = "/tmp/deployment-luks.key"; # Path only used when formatting !
              # askPassword = true;
              settings.allowDiscards = true;
              settings.bypassWorkqueues = true;
              content = {
                # NOTE; We're following the example here with LVM on top of LUKS.
                # THE REASON IS BECAUSE OF SECTOR ALIGNMENT AND EXPECTATIONS ! LVM provides flexible sector sizes detached from
                # underlying systems.
                # Using GPT inside the LUKS container makes the situation complicated, I'm not grasping this entirely myself, but
                # default sector sizes for GPT partition layouts is 512B and LUKS by default has a minimum sector size of 4096B (4K)
                # and you cannot go below that sector size on top (sector size is the minimum addressable unit).
                # For some reason the stage-1 environment doesn't like GPT sectors of 4096 bytes (in the current setup) and fails
                # to load its partitions. There are no issues with 4K sectors on physical hard disks though.. /shrug
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          raw = {
            # Refer to this partition by "/dev/pool/zram-backing-device"
            name = "zram-backing-device";
            size = "2G";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
            };
          };
        };
      };
    };
  };
}
