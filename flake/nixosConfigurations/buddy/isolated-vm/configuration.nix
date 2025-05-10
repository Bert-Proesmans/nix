{ flake, ... }: {
  # NOTE; Isolated here means there is _no_ communication between nor proxied through hypervisor and virtual machine.
  # At most some pre-seeding.
  microvm.vms."isolated" = {
    autostart = true;
    specialArgs = { inherit flake; };
    config = { lib, modulesPath, ... }: {
      _file = ./configuration.nix;

      imports = [
        (modulesPath + "/profiles/minimal.nix") # Reduce closure size
        (modulesPath + "/profiles/hardened.nix") # ~~eeergh.. unsure if the ratio performance/security is worth it
        ./routed-dns/configuration.nix
      ];

      config = {
        system.stateVersion = "24.11";
        nixpkgs.hostPlatform = lib.systems.examples.gnu64;

        # Configure default root filesystem minimizing ram usage.
        # NOTE; All required files for boot and configuration are within the /nix mount!
        # What's left are temporary files, application logs and -artifacts, and to-persist application data.
        fileSystems."/" = {
          device = "rootfs";
          fsType = "tmpfs";
          options = [ "size=100M,mode=0755" ];
          neededForBoot = true;
        };

        microvm = {
          hypervisor = "cloud-hypervisor";
          vcpu = 1;
          # Total memory available to machine (includes dynamically plugged memory)
          # NOTE; Increasing this value will not improve performance meaningfully, 1vCPU is a real bottleneck.
          hotplugMem = 1024; # MiB
          # Amount of dynamic memory provided at boot and which can be reclaimed later by the hypervisor.
          # NOTE; The machine effectively has (1024 - 512) = 512MB memory during runtime
          hotpluggedMem = 512; # MiB
          # WARN; hugetable filesystem is enabled by default in modern kernels. Lots of old and now incomplete information 
          # is still floating around on the internet.
          # NOTE; Reading lots of *small files* has additional syscall overhead on both hypervisor and guest, so performance gains
          # from huge pages alone are low.
          # With this setting cloud-hypervisor backs all guest RAM with hugetables. The performance gains are virtiofsd pushing 
          # more data per syscall into the guest ring buffers, under expectation that it already uses bigger buffers on 
          # the hypervisor. BUT the pipeline also uses unix socket transport using fixed buffer lengths of 208KB 
          # (/proc/sys/net/core/rmem_default) so AF_UNIX becomes the next bottleneck.
          hugepageMem = true;
          graphics.enable = false;
          optimize.enable = true; # Reduce closure size

          interfaces = [{
            type = "macvtap";
            macvtap = {
              # This sets up an isolated networking stack for the virtual machine, the virtual machine acts as a completely separate
              # machine on the network.
              # NOTE; Private allows the VMs to only talk to the network, connecting to the hypervisor requires an external switched
              # network.
              mode = "private";
              link = "main";
            };
            id = "vmac-isolated";
            mac = "26:fa:77:05:26:bc"; # randomly generated
          }];

          virtiofsd = {
            extraArgs = [
              # Enable proper handling of bindmounts in shared directory!
              "--announce-submounts"
              # ZFS does in-memory file caching for us!
              "--cache never"
            ];
          };

          # It is highly recommended to share the host's nix-store with the VMs to prevent building huge boot/rootFS images. These
          # images are stored inside /nix/store bloating disk space usage.
          shares = [{
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
            # ERROR; The parameter below is only used for p9 sharing. This is _not_ the same as virtiofs' accessmode!
            # securityModel = "mapped";
          }];
        };
      };
    };
  };
}
