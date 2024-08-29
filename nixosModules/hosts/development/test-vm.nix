{ lib, flake, profiles, home-configurations, meta-module, ... }: {
  sops.secrets."test-vm/ssh_host_ed25519_key" = {
    # For virtio ssh
    mode = "0400";
    restartUnits = [ "microvm@test.service" ]; # Systemd interpolated service
  };

  microvm.vms.test = {
    autostart = true;
    specialArgs = { inherit lib flake profiles; };
    config = { lib, profiles, ... }: {
      _file = ./test-vm.nix;

      imports = [
        profiles.qemu-guest-vm
        (meta-module "test")
        ../test.nix # VM config
      ];

      config = {
        microvm.vsock.cid = 55;
        microvm.interfaces = [{
          type = "macvtap";
          macvtap = {
            # Private allows the VMs to only talk to the network, no host interaction.
            # That's OK because we use VSOCK to communicate between host<->guest!
            mode = "private";
            link = "main";
          };
          id = "vmac-test";
          mac = "6a:33:06:88:6c:5b"; # randomly generated
        }];

        microvm.shares = [{
          source = "/run/secrets/test-vm"; # RAMFS coming from sops
          mountPoint = "/seeds";
          tag = "secret-seeds";
          proto = "virtiofs";
        }];
      };
    };
  };
}
