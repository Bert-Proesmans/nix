{ flake, ... }:
{
  systemd.tmpfiles.settings."hugepages" = {
    "/sys/kernel/mm/transparent_hugepage/enabled".w = {
      # Reduce random latency on defragmentation of memory pages.
      # Only use explicit huge pages through madvice.. or
      # Only use explicit huge pages through hugetblfs, see nr_hugepages.
      argument = "madvise"; # enum
    };

    "/proc/sys/vm/nr_hugepages".w = {
      # Set the amount of huge pages to use by the kernel
      # NOTE; At a default size of 2MB (unless adjusted), we're reserving 2GB of RAM.
      argument = "1024"; # units
    };
  };

  # NOTE; Isolated here means there is _no_ communication between nor proxied through hypervisor and virtual machine.
  # At most some pre-seeding.
  microvm.vms."isolated" = {
    autostart = true;
    config =
      { lib, modulesPath, ... }:
      {
        _file = ./default.nix;

        imports = [
          (modulesPath + "/profiles/minimal.nix") # Reduce closure size
          (modulesPath + "/profiles/hardened.nix") # ~~eeergh.. unsure if the ratio performance/security is worth it
          flake.profiles.dns-server
        ];

        config = {
          system.stateVersion = "24.11";
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;

          microvm = {
            hypervisor = "cloud-hypervisor";
            vcpu = 1;
            # Total memory available to machine (includes dynamically plugged memory)
            # NOTE; Increasing this value will not improve performance meaningfully, 1VCPU is a real bottleneck.
            hotplugMem = 1024; # MB
            # Amount of dynamic memory provided at boot and which can be reclaimed later by the hypervisor.
            # NOTE; The machine effectively has (1024 - 512) = 512MB memory during runtime
            hotpluggedMem = 512; # MB
            # WARN; hugetable filesystem is enabled by default in modern kernels. Lots of old (and now incomplete) information
            # is still floating around on the internet.
            # NOTE; Reading lots of *small files* has additional syscall overhead on both hypervisor and guest, so performance gains
            # from huge pages alone are low.
            # With this setting cloud-hypervisor backs all guest RAM with hugetables. The performance gains are virtiofsd pushing
            # more data per syscall into the guest ring buffers. (but the pipeline also uses unix socket transport etc soo.. low
            # improvements)
            hugepageMem = true;
            graphics.enable = false;
            optimize.enable = true; # Reduce closure size

            interfaces = [
              {
                type = "macvtap";
                macvtap = {
                  # Private allows the VMs to only talk to the network, no host interaction.
                  mode = "private";
                  link = "main";
                };
                id = "vmac-isolated";
                mac = "26:fa:77:05:26:bc"; # randomly generated
              }
            ];

            virtiofsd = {
              extraArgs = [
                # Enable proper handling of bindmounts in shared directory!
                "--announce-submounts"
                # ZFS does in-memory file caching for us!
                # HELP; Toggle this for different filesystem backend situations!
                "--cache never"
              ];
            };

            # It is highly recommended to share the host's nix-store with the VMs to prevent building huge images.
            shares = [
              {
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                tag = "ro-store";
                proto = "virtiofs";
                # ERROR; The parameter below is only used for p9 sharing. This is _not_ the same as virtiofs' accessmode!
                # securityModel = "mapped";
              }
            ];
          };

          # Configure default root filesystem minimizing ram usage.
          # NOTE; All required files for boot and configuration are within the /nix mount!
          # What's left are temporary files, application logs and -artifacts, and to-persist application data.
          #
          # WARN; Custom overide priority so the virtual machine could define volumes to mount at "/"
          fileSystems."/" = {
            device = "rootfs";
            fsType = "tmpfs";
            options = [ "size=100M,mode=0755" ];
            neededForBoot = true;
          };
        };
      };
  };
}
