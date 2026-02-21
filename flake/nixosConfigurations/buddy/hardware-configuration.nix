{ lib, config, ... }:
{
  # Define the platform type of the target configuration
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;

  # Enables (nested) virtualization through hardware acceleration.
  boot.kernelModules = [ "kvm-amd" ];
  boot.kernelParams = [
    # kernel: clocksource: timekeeping watchdog on CPU0: Marking clocksource 'tsc' as unstable because the skew is too large:
    # kernel: clocksource:                       'hpet' wd_nsec: 503380178 wd_now: 2257dd0 wd_last: 1b78390 mask: ffffffff
    # kernel: clocksource:                       'tsc' cs_nsec: 504262388 cs_now: d82177fe0 cs_last: d22179660 mask: ffffffffffffffff
    # kernel: clocksource:                       Clocksource 'tsc' skewed 882210 ns (0 ms) over watchdog 'hpet' interval of 503380178 ns (503 ms)
    # kernel: clocksource:                       'tsc' is current clocksource.
    # kernel: TSC found unstable after boot, most likely due to broken BIOS. Use 'tsc=unstable'.
    "tsc=unstable"
  ];
  hardware.cpu.amd.updateMicrocode = true;

  # GPU driver being amdgpu (upstreamed in linux kernel)
  # Acceleration and Vulkan through MESA RADV (_not_ AMDVLK)
  # If AMDVLK is required, see https://wiki.nixos.org/wiki/AMD_GPU
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true; # contains required amdgpu configuration blobs
  hardware.graphics.extraPackages = [
    # All hardware acceleration packages should have been included already (delivered by MESA)
    # sudo vainfo --display drm --device /dev/dri/renderD128
    # Trying display: drm
    # libva info: VA-API version 1.22.0
    # libva info: Trying to open /run/opengl-driver/lib/dri/radeonsi_drv_video.so
    # libva info: Found init function __vaDriverInit_1_22
    # libva info: va_openDriver() returns 0
    # vainfo: VA-API version: 1.22 (libva 2.22.0)
    # vainfo: Driver version: Mesa Gallium driver 25.0.6 for AMD Radeon Vega 3 Graphics (radeonsi, raven, ACO, DRM 3.61, 6.12.29)
    # vainfo: Supported profile and entrypoints
    #       VAProfileMPEG2Simple            : VAEntrypointVLD
    #       VAProfileMPEG2Main              : VAEntrypointVLD
    #       VAProfileVC1Simple              : VAEntrypointVLD
    #       VAProfileVC1Main                : VAEntrypointVLD
    #       VAProfileVC1Advanced            : VAEntrypointVLD
    #       VAProfileH264ConstrainedBaseline: VAEntrypointVLD
    #       VAProfileH264ConstrainedBaseline: VAEntrypointEncSlice
    #       VAProfileH264Main               : VAEntrypointVLD
    #       VAProfileH264Main               : VAEntrypointEncSlice
    #       VAProfileH264High               : VAEntrypointVLD
    #       VAProfileH264High               : VAEntrypointEncSlice
    #       VAProfileHEVCMain               : VAEntrypointVLD
    #       VAProfileHEVCMain               : VAEntrypointEncSlice <- Can hardware accelerated encode into HEVC
    #       VAProfileHEVCMain10             : VAEntrypointVLD
    #       VAProfileJPEGBaseline           : VAEntrypointVLD
    #       VAProfileVP9Profile0            : VAEntrypointVLD
    #       VAProfileVP9Profile2            : VAEntrypointVLD
    #       VAProfileNone                   : VAEntrypointVideoProc
  ];

  systemd.tmpfiles.settings."hugepages" = {
    "/sys/kernel/mm/transparent_hugepage/enabled".w = {
      # [always] Always give out pages in size bigger than 4KiB.. or <= impacts latency on allocations due to dynamic compaction
      # [madvise] Only give out explicit huge pages through madvice.. or
      # [never] Only use explicit huge pages through hugetblfs, see nr_hugepages
      argument = "madvise"; # enum
    };

    # ERROR; CPU's can have hardware support for hugepages, so setting a custom size could reduce performance to gain less overhead
    # losses. Only the last memory page in an allocation is _possibly_ not efficiently used, this is not worth optimizing.
    # The default pagesize is set by the kernel to 2 mebibytes (MiB), a multiple of 4 kibibytes (KiB).
    # SEEALSO; `cat /proc/meminfo | grep Hugepagesize`

    "/proc/sys/vm/nr_hugepages".w = {
      # Set the size of static huge pages pool for the kernel to use
      # HELP; Make pages available considering;
      #  - The sum of RAM of your virtual machine guests
      #     - cloud-hypervisor will fall back to non-huge pages if sufficient amount not available
      #  - The sum of memory required for large scale data processing and memory mapped algorithms
      #
      # NOTE; At a default size of 2MiB (unless adjusted), we're reserving 2GiB of RAM.
      argument = "1024"; # units
    };
  };

  environment.variables.LD_LIBRARY_PATH = [
    "/run/opengl-driver/lib" # OpenGL shared libraries from graphics driver
  ];

  networking = { inherit (config.proesmans.facts.self) hostId; };

  systemd.network =
    let
      managementMac = config.proesmans.facts.self.hardware.lan.address;
    in
    {
      links = {
        "10-upstream" = {
          matchConfig.MACAddress = managementMac;
          linkConfig.Alias = "Internet uplink";
          linkConfig.AlternativeName = "main";
        };
      };

      networks = {
        "30-lan" = {
          matchConfig.MACAddress = managementMac;
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
        };
      };
    };
}
