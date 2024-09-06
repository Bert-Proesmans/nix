{ lib, config, flake, profiles, meta-module, ... }: {
  sops.secrets."dns-vm/ssh_host_ed25519_key" = {
    restartUnits = [
      # New ssh key requires restart of guest
      "microvm@dns.service"
    ];
  };

  microvm.vms."dns" =
    let
      parent-hostname = config.networking.hostName;
      guest-ssh-key = config.sops.secrets."dns-vm/ssh_host_ed25519_key".path;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake profiles; };

      # The configuration for the MicroVM.
      # Multiple definitions will be merged as expected.
      config = { config, profiles, ... }: {
        _file = ./dns-vm.nix;

        imports = [
          profiles.qemu-guest-vm
          (meta-module "dns")
          ../dns.nix # VM config
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

          microvm.suitcase.secrets = {
            "ssh_host_ed25519_key".source = guest-ssh-key;
          };

          services.openssh.hostKeys = [
            {
              path = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
              type = "ed25519";
            }
          ];
          systemd.services.sshd.unitConfig.ConditionPathExists = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
          systemd.services.sshd.serviceConfig.StandardOutput = "journal+console";
        };
      };
    };
}
