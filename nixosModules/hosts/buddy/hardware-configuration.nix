{ lib, ... }: {
  imports = [
    ./zfs.nix
  ];

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

  environment.variables.LD_LIBRARY_PATH = [
    "/run/opengl-driver/lib" # OpenGL shared libraries from graphics driver
  ];

  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  networking.hostId = "525346fb";

  systemd.network.links = {
    "10-upstream" = {
      matchConfig.MACAddress = "b4:2e:99:15:33:a6";
      linkConfig.Alias = "Internet uplink";
      linkConfig.AlternativeName = "main";
    };
  };

  systemd.network.networks = {
    "30-lan" = {
      matchConfig.MACAddress = "b4:2e:99:15:33:a6";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
