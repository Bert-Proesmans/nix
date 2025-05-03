{ lib, config, ... }: {
  imports = [
    ./zfs.nix
    ./filesystems.nix
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
