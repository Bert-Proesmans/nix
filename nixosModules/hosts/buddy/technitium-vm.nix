{ lib, pkgs, config, flake, profiles, home-configurations, meta-module, ... }: {
  sops.secrets."technitium-vm/ssh_host_ed25519_key" = {
    mode = "0400";
  };

  microvm.vms.technitium = {
    autostart = true;
    specialArgs = { inherit lib flake profiles; };

    # The configuration for the MicroVM.
    # Multiple definitions will be merged as expected.
    config = { lib, config, profiles, ... }: {
      _file = ./technitium-vm.nix;

      imports = [
        profiles.qemu-guest-vm
        (meta-module "DNS")
        ../DNS.nix # VM config
      ];

      config = {
        # ERROR; Number must be unique for each VM!
        # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
        microvm.vsock.cid = 210;

        microvm.interfaces = [{
          type = "macvtap";
          macvtap = {
            # Private allows the VMs to only talk to the network, no host interaction.
            # That's OK because we use VSOCK to communicate between host<->guest!
            mode = "private";
            link = "main";
          };
          id = "vmac-technitium";
          mac = "26:fa:77:05:26:bc"; # randomly generated
        }];

        microvm.shares = [ ];
      };
    };
  };
}
