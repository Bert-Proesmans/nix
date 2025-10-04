{
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  # Attempt to reduce memory pressure as much as possible! This virtual machine only has 1GB of RAM!
  boot.kernelParams = [
    # We want ZRAM (in-ram swap device with compression).
    # ZSWAP (a swap cache writing compressed pages to disk-baked swap) conflicts with this configuration.
    # ZRAM is a better iteration on ZSWAP because of automatic eviction of uncompressable data.
    "zswap.enabled=0"
  ];

  boot.kernel.sysctl = {
    # REF; https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
    "vm.swappiness" = 200;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };

  systemd.oomd = {
    # Can replace earlyoom. Kills entire resource slices if something misbehaves.
    # WARN; Functional at this point in time, but services/systemd units need more slice support. There need to be more
    # slices that allow oomd to kill with higher precision. The current setup risks killing the user session (user slice)
    # or system (system/root slice) if there is resource overusage without a more specific slice underneath those.
    #
    # Configure resource slice limits through "sliceConfig" per slice individually. Systemd out-of-memory daemon reads that
    # configuration to react. eg
    # systemd.slices.system-immich.sliceConfig = {
    #  ManagedOOMMemoryPressure = "kill"; # <-- Activates monitoring of this slice by OOM daemon
    #  ManagedOOMMemoryPressureLimit = "80%"; # <-- [optional] Act on (sub-)slice if memory usage was above limit for DefaultMemoryPressureDurationSec
    # };
    # SEEALSO; https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html#Memory%20Pressure%20Control
    #
    # HELP; Keep enabled, better integration will come automatically. Do not enable earlyoomd, the downsides to its reaping technique
    # is also bad.
    enable = true;
    # NOTE; These high-level slices are set to 80% pressure, since they potentially hold the entire system.
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
    extraConfig.DefaultMemoryPressureLimit = "60%"; # Systemd default
    extraConfig.DefaultMemoryPressureDurationSec = "20s"; # Fedora default
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
    # NOTE; Bytes written to the SWAP device are compressed. It's impossible to predict compression ratios.
    # The only number we can set is the maximum total size of the swap device.
    #
    # HELP; Discover the typical compression ratio. Given a ratio, work backwards from the amount of physical RAM that can be comfortably
    # allocated as SWAP. Don't forget to consider overhead (couple of megabytes)!
    # EXAMPLE;
    # - typical compression ratio; 10x
    # - typical overhead; 40MB
    # - total RAM; 1GB
    # - required RAM; 600MB (kernel + systemd + services ~+ file buffer/cache)
    # => 400MB for SWAP allocation => (400MB -40MB) *10 => 3600MB total SWAP device size
    #
    # HELP; SWAP is used as scratchspace to perform bookkeeping and storing idle memory pages. With services needing a couple of MBs RAM
    # there is no way anything above 1GB is used (realistically). The default settings are good enough!
    memoryPercent = 50; # default
    memoryMax = null; # default
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
