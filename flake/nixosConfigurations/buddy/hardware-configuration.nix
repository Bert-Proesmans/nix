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
      # Reduce random latency on defragmentation of memory pages.
      # Only use explicit huge pages through madvice.. or
      # Only use explicit huge pages through hugetblfs, see nr_hugepages.
      argument = "madvise"; # enum
    };

    "/proc/sys/vm/nr_hugepages".w = {
      # Set the amount of huge pages to use by the kernel
      # HELP; Try to make pages available equal to the sum of your virtual machine guests, but this is not required per se
      # and the hypervisor control should fall back to not hugepage memory.
      #
      # NOTE; At a default size of 2MB (unless adjusted), we're reserving 2GB of RAM.
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
