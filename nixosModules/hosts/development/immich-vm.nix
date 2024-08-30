{ lib, flake, profiles, meta-module, ... }: {
  sops.secrets."immich-vm/ssh_host_ed25519_key" = {
    # For virtio ssh
    mode = "0400";
    restartUnits = [ "microvm@immich.service" ]; # Systemd interpolated service
  };

  microvm.vms.immich = {
    autostart = true;
    specialArgs = { inherit lib flake profiles; };
    config = { profiles, ... }: {
      _file = ./immich-vm.nix;

      imports = [
        profiles.qemu-guest-vm
        (meta-module "immich")
        ../photos.nix # VM config
      ];

      config = {
        nixpkgs.hostPlatform = lib.systems.examples.gnu64;
        microvm.vcpu = 2;
        microvm.mem = 4096; # MB
        microvm.vsock.cid = 42;

        microvm.interfaces = [{
          type = "macvtap";
          macvtap = {
            # Private allows the VMs to only talk to the network, no host interaction.
            # That's OK because we use VSOCK to communicate between host<->guest!
            mode = "private";
            link = "main";
          };
          id = "vmac-immich";
          mac = "42:de:e5:ce:a8:d6"; # randomly generated
        }];

        microvm.shares = [{
          source = "/run/secrets/immich-vm"; # RAMFS coming from sops
          mountPoint = "/seeds";
          tag = "secret-seeds";
          proto = "virtiofs";
        }];
      };
    };
  };
}
