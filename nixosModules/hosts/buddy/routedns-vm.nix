{ lib, config, flake, profiles, meta-module, ... }: {
  sops.secrets."routedns-vm/ssh_host_ed25519_key" = {
    mode = "0400"; # Required by sshd
    restartUnits = [
      # New secrets are a new directory (new generation) and bind mount must be updated
      "shared-routedns-seeds.mount"
      # New ssh key requires restart of guest
      "microvm@routedns.service"
    ];
  };

  # Mounted at /shared/routedns/<mount-name>
  proesmans.mount-central = {
    defaults.after-units = [ "zfs-mount.service" ];
    directories."routedns".mounts = {
      "seeds".source = "/run/secrets/routedns-vm";
    };
  };

  systemd.services."microvm-virtiofsd@routedns".unitConfig = {
    RequiresMountsFor = config.proesmans.mount-central.directories."routedns".bind-paths;
  };

  microvm.vms."routedns" =
    let
      parent-hostname = config.networking.hostName;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake profiles; };

      # The configuration for the MicroVM.
      # Multiple definitions will be merged as expected.
      config = { config, profiles, ... }: {
        _file = ./routedns-vm.nix;

        imports = [
          profiles.qemu-guest-vm
          (meta-module "DNS")
          ../DNS.nix # VM config
        ];

        config = {
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;
          # ERROR; Number must be unique for each VM!
          # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
          microvm.vsock.cid = 210;

          proesmans.facts.tags = [ "virtual-machine" ];
          proesmans.facts.meta.parent = parent-hostname;

          microvm.interfaces = [{
            type = "macvtap";
            macvtap = {
              # Private allows the VMs to only talk to the network, no host interaction.
              # That's OK because we use VSOCK to communicate between host<->guest!
              mode = "private";
              link = "main";
            };
            id = "vmac-routedns";
            mac = "26:fa:77:05:26:bc"; # randomly generated
          }];

          microvm.shares = [
            {
              source = "/shared/routedns";
              mountPoint = "/data";
              tag = "state-routedns";
              proto = "virtiofs";
            }
          ];
        };
      };
    };
}
