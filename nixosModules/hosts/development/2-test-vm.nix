{ lib, flake, special, meta-module, config, ... }: {
  sops.secrets."test-vm/ssh_host_ed25519_key" = {
    restartUnits = [ config.systemd.services."microvm@2-test".name ]; # Systemd interpolated service
  };

  microvm.vms."2-test" =
    let
      parent-hostname = config.networking.hostName;
      guest-ssh-key = config.sops.secrets."test-vm/ssh_host_ed25519_key".path;
    in
    {
      autostart = false;
      specialArgs = { inherit lib flake special; };
      config = { special, config, ... }: {
        _file = ./2-test-vm.nix;

        imports = [
          special.profiles.qemu-guest-vm
          #special.profiles.crosvm-guest
          (meta-module "2-test")
          ../test.nix # VM config
        ];

        config = {
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;
          microvm.vsock.cid = 90000;
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
            id = "vmac-2-test";
            mac = "9e:5f:ca:0b:83:8d"; # randomly generated
          }];

          # microvm.central.shares = [
          #   ({
          #     source = "/var/dir-share";
          #     mountPoint = "/var/dir-share";
          #     tag = "dir-share";
          #   })
          # ];

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
