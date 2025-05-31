{ lib, modulesPath, ... }: {
  #
  # Boot on AMD 1OCPU
  #
  # NOTE; nixos-anywhere should be able to "stream-install" as well in limited RAM circumstances. The instructions below are doing 
  # the manual work for minimal RAM impact.
  # WARN; The disko configuration will ask for a password on luks format, but interactive input during nixos-anywhere install doesn't
  # work. The process will hang forever waiting for input. To fix;
  #   - OR Run disko formatting interactively 
  #   - OR configure a keypath and upload the key as deployment argument (--disk-encryption-keys)
  #
  # 1. Configure VPS
  #   1. Choose a minimal ubuntu image
  #   2. Enter SSH pubkey
  # 2. SSH into host (ssh ubuntu@<$IP>)
  # 3. Cleanup running processes to free RAM (`top`, press e, press shift+m)
  #   1. sudo systemctl --no-block stop snapd snap* unattended-upgrades
  #   2. echo 3 | sudo tee /proc/sys/vm/drop_caches
  # 4. Kernel exec (K'exec) into nixos system
  #   1. curl -L https://github.com/nix-community/nixos-images/releases/latest/download/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz | tar -xzf- -C /tmp && sudo /tmp/kexec/run
  # 5. SSH into kexec (ssh root@<$IP>), or use console connection
  # 6. Build and copy format script of host
  #   2. nix build --no-link ./flake#nixosConfigurations.01-fart.config.system.build.diskoScript
  #   1. DISKO="$(nix path-info ./flake#nixosConfigurations.01-fart.config.system.build.diskoScript)"
  #   3. nix copy --substitute-on-destination --to "ssh-ng://root@$IP" "$DISKO" --no-check-sigs
  # 7. Execute format script
  #   1. ssh "root@$IP" "$DISKO"
  # NOTE; Disko leaves the new root filesystem mounted at /mnt
  # 8. Install the nixos configuration
  #   1. nix build --no-link ./flake#nixosConfigurations.01-fart.config.system.build.toplevel
  #   2. HOST="$(nix path-info ./flake#nixosConfigurations.01-fart.config.system.build.toplevel)"
  #   WARN; nixos-install has two modes; 1. build the target system from sources (in nix store) / 2. copy built system from a local nix store
  #         But we cannot build on FART and we're running completely from RAM (aka no persistent attached storage to boot NixOS from).
  #         So;
  #         - The built system is copied into /mnt(/nix) using the remote-store feature.
  #         - nixos-install is called with a root argument to assume '/nix/store' as '/mnt/nix/store' and install correctly
  #   ERROR; The nix copy operation could hang due to kernel swapping, if it looks like progress stalled cancel the command and wait
  #          for the swapping to end. Then execute the same command again.
  #   3. nix copy --substitute-on-destination --to "ssh-ng://root@$IP?remote-store=/mnt&" "$HOST" --no-check-sigs
  #   4. ssh "root@$IP" nixos-install --no-root-password --no-channel-copy --root /mnt --system "$HOST"
  # 9. Reboot system; ssh "root@$IP" reboot
  # DONE.

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
  ];

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
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" ];
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

      # Mark all pages older than provided seconds as idle. [ONE-TIME]
      # = 4 hours
      # REF; https://docs.kernel.org/admin-guide/blockdev/zram.html#writeback
      echo 14400 > /sys/block/zram0/idle

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
              # ERROR; This configuration cannot be non-interactively deployed through nixos-anywhere !!
              # This setting will request an encryption password during execution of format script.
              # Generate and store a new key using; 
              # tr -dc '[:alnum:]' </dev/urandom | head -c64
              askPassword = true;
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

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "25.05";
}
