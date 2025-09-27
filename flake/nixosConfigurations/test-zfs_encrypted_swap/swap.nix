{ ... }:
{
  # Attempt to reduce memory pressure as much as possible! This virtual machine only has 1GB of RAM!
  boot.kernelParams = [
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

  systemd.oomd = {
    # Newer iteration of earlyoom!
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    extraConfig.DefaultMemoryPressureDurationSec = "30s"; # Default
  };

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
      # ERROR; Does NOT work without CONFIG_ZRAM_TRACK_ENTRY_ACTIME ! See below for alternative
      # Mark all pages older than provided seconds as idle.
      # REF; https://docs.kernel.org/admin-guide/blockdev/zram.html#writeback
      # echo "14400" > /sys/block/zram0/idle # 4 hours


      # NOTE; The zram device _does not_ automatically manage least-recently-used (LRU) eviction!
      # ERROR; Out-of-the-box Linux kernel in NixOS is _not configured_ with CONFIG_ZRAM_TRACK_ENTRY_ACTIME! There is no idle time
      # tracking on zram pages, so this impacts how we handle writeback of idle pages!
      #
      # Without automatic idle-marker tracking, we'll do this ourselves in a two step process.
      # 1. Writeback/evict marked pages
      # 2. Mark all pages currently stored as idle
      #   - Pages' idle mark will be removed on retrieval/set

      # Evict pages from RAM.
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

      # Mark all remaining pages as idle.
      # REF; https://docs.kernel.org/admin-guide/blockdev/zram.html#writeback
      echo "all" > /sys/block/zram0/idle
    '';
  };
}
