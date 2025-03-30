{ lib, config, ... }: {
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

  # Don't setup /tmp in RAM, but backed by /var/tmp
  fileSystems."/tmp" = {
    depends = [ "/var/tmp" ];
    device = "/var/tmp";
    fsType = "none";
    options = [ "rw" "noexec" "nosuid" "nodev" "bind" ];
  };

  disko.devices.zpool.storage.datasets = {
    "cache" = {
      type = "zfs_fs";
      mountpoint = "/var/cache";
      options.mountpoint = "legacy";
    };

    "log" = {
      type = "zfs_fs";
      mountpoint = "/var/log";
      options.mountpoint = "legacy";
    };
  };

  # TODO; Consolidate backup and move into separate configuration file
  systemd.tmpfiles.settings."1-base-datasets" = {
    # Make a root owned landing zone for backup data
    "/persist" = {
      # Create directory owned by root
      d = {
        user = config.users.users.root.name;
        group = config.users.groups.root.name;
        mode = "0700";
      };
      # Set ACL defaults
      # "A+".argument = "group::r-X,other::---,mask::r-x,default:group::r-X,default:other::---,default:mask::r-X";
    };
  };

  networking = { inherit (config.proesmans.facts.self) hostId; };

  systemd.network =
    let
      managementMac = lib.mapAttrsToList (m: v: builtins.elem "management" v.tags) config.proesmans.facts.self.macAddresses;
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
