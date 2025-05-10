{ lib, config, ... }: {
  # Define the platform type of the target configuration
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;

  # Enables (nested) virtualization through hardware acceleration.
  # There is no harm in having both modules loaded at the same time, also no real overhead.
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = true;

  # GPU driver being amdgpu (upstreamed in linux kernel)
  # Acceleration and Vulkan through MESA RADV (_not_ AMDVLK)
  # If AMDVLK is required, see https://wiki.nixos.org/wiki/AMD_GPU
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true; # contains required amdgpu configuration blobs

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
      managementMac = lib.mapAttrsToList (_: v: v.address)
        (lib.filterAttrs (_m: v: builtins.elem "management" v.tags) config.proesmans.facts.self.macAddresses);
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
