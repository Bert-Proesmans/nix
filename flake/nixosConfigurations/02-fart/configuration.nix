{
  lib,
  modulesPath,
  config,
  ...
}:
{
  #
  # Boot on AMD 1OCPU
  # => See comments in 01-fart/configuration.nix

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
  ];

  system.stateVersion = "25.05";
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm-amd" ];
  boot.kernelParams = [
    "console=ttyS0,9600" # Required for OCI attached console
    # We want ZRAM (in-ram swap device with compression).
    # ZSWAP (a swap cache writing compressed pages to disk-baked swap) conflicts with this configuration.
    # ZRAM is a better iteration on ZSWAP because of automatic eviction of uncompressable data.
    "zswap.enabled=0"

    # Allow emergency shell in stage-1-init
    "boot.shell_on_fail" # DEBUG
  ];
  boot.kernel.sysctl = {
    # REF; https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
    "vm.swappiness" = 200;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.tmp.useTmpfs = false; # Only have 1G RAM
  boot.tmp.cleanOnBoot = true;

  zramSwap = {
    # NOTE; Using ZRAM; in-memory swap device with compressed pages, backed by block device to hold incompressible and memory overflow.
    # ERROR; The default kernel page controller does not manage evictions between swap devices of different priority! Devices are
    # filled in priority order until they cannot hold more data. This means that a full zram device with stale data causes next evictions
    # to be written to the next swap device with lower priority.
    # ERROR; Managing least-recently-used (LRU) inside ZRAM will improve latency, but this isn't how the mechanism exactly works either.
    # The writeback device will receive _randomly_ chosen 'idle' pages, causing high variance in latency! There is a configurable access
    # timer, however, that marks pages as idle automatically.
    enable = true;
    # NOTE; Refer to this swap device by "/sys/block/zram0"
    swapDevices = 1;
    memoryMax = 2 * 1024 * 1024 * 1024; # (2GB) Bytes, total size of swap device aka max size of uncompressed data
    priority = 5; # default
    algorithm = "zstd";
    writebackDevice = "/dev/pool/zram-backing-device"; # block device, see disko config
  };

  systemd.services."zram0-maintenance" = {
    enable = true;
    description = "Maintain zram0 data";
    startAt = "*-*-* 00/1:00:00"; # Every hour
    requisite = [ "systemd-zram-setup@zram0.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = "no";
    enableStrictShellChecks = true;
    script = ''
      # NOTE; The zram device _does not_ automatically manage least-recently-used (LRU) eviction!
      # ERROR; Out-of-the-box Linux kernel in NixOS is _not configured_ with CONFIG_ZRAM_TRACK_ENTRY_ACTIME! There is no idle time
      # tracking on zram pages, so this impacts how we handle writeback of idle pages!
      #
      # Without idle-marking, we'll move all pages marked idle during the previous execution of this script.
      # 1. Writeback marked pages
      # 2. Mark all pages currently stored as idle
      #   - Pages' idle mark will be removed on retrieval/set

      # Evict pages from RAM. [ONE-TIME]
      #
      # [huge] Write incompressible page clusters(?) to backing device
      # [idle] Write idle pages to backing device
      # [huge_idle] Equivalent to 'huge' and 'idle'
      # [incompressible] same as 'huge', with minor difference that 'incompressible' works in individual(?) pages
      # REF; https://docs.kernel.org/admin-guide/blockdev/zram.html#writeback
      #
      # There is no difference between incompressible and huge if the page cluster size is set to 0.
      # SEEALSO; boot.kernel.sysctl."vm.page-cluster"
      echo "huge_idle" > /sys/block/zram0/writeback

      # Mark all pages as idle. [ONE-TIME]
      # REF; https://docs.kernel.org/admin-guide/blockdev/zram.html#writeback
      echo "all" > /sys/block/zram0/idle

      # ERROR; Does NOT work without CONFIG_ZRAM_TRACK_ENTRY_ACTIME !
      # Mark all pages older than provided seconds as idle. [ONE-TIME]
      # = 4 hours
      # REF; https://docs.kernel.org/admin-guide/blockdev/zram.html#writeback
      # echo "14400" > /sys/block/zram0/idle
    '';
  };

  systemd.oomd = {
    # Newer iteration of earlyoom!
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    extraConfig.DefaultMemoryPressureDurationSec = "30s"; # Default
  };

  networking.useDHCP = true;
  networking.useNetworkd = true;

  # Slows down write operations considerably
  nix.settings.auto-optimise-store = lib.mkForce false;

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

  # Setup runtime secrets and corresponding ssh host key
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.enable = true;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Make me an admin!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "wheel" # Allows sudo access
      "systemd-journal" # Read the systemd service journal without sudo
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };

  sops.secrets.tailscale_connect_key.owner = "root";
  services.tailscale = {
    enable = true;
    disableTaildrop = true;
    openFirewall = true;
    useRoutingFeatures = "none";
    authKeyFile = config.sops.secrets.tailscale_connect_key.path;
    extraDaemonFlags = [ "--no-logs-no-support" ];
  };
}
