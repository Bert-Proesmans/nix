{ lib, config, flake, special, meta-module, ... }: {
  sops.secrets = {
    "proxy-vm/ssh_host_ed25519_key" = {
      # New ssh key requires restart of guest
      restartUnits = [ config.systemd.services."microvm@proxy".name ];
    };
  };

  security.acme.certs."alpha.proesmans.eu" = {
    reloadServices = [ config.systemd.services."microvm@proxy".name ];
  };
  systemd.services."microvm@proxy" = {
    # Wait until the certificates exist before starting the guest
    unitConfig.ConditionPathExists = "${config.security.acme.certs."alpha.proesmans.eu".directory}/fullchain.pem";
  };

  # ERROR; AF_VSOCK packets are dropped by Qemu vhost-vsock{-pci} driver when the arrive at the host side
  # without correct CID. AKA using connect flag VMADDR_FLAG_TO_HOST to setup a proxied VSOCK connection between sibling
  # virtual machines is not possible currently!
  # REF; https://lore.kernel.org/kvm/nojtsdora7chbhnblvygozoa4qui3ghivndvg5ixbsgebos4hg@e2jldxpf7sum/
  # ASIDE; There was talk about adding "-object vsock-forward", but that didn't get implemented yet. Something to do
  # with firewalling between siblings... 
  #
  # NOTE; vhost-user-vsock seems like the current future for sibling communications, "vhost-user-vsock" is a different qemu backend
  # driver that needs more configuration and a user-space proxy daemon.
  # REF; https://github.com/rust-vmm/vhost-device/tree/main/vhost-device-vsock#sibling-vm-communication
  #
  # NOTE; Alternatively, we could literally hairpin between guests and hosts by agreeing on ports.
  #
  proesmans.vsock-proxy.proxies =
    let
      cid-shared-hosts = lib.pipe flake.outputs.host-facts [
        (lib.filterAttrs (_: v: v.meta.parent == config.networking.hostName))
        (lib.mapAttrs' (_: v: lib.nameValuePair v.host-name v.meta.vsock-id))
      ];
    in
    [
      ({
        description = "Proxy <-> Photos";
        listen.vsock.cid = -1;
        listen.port = 10000;
        transmit.vsock.cid = cid-shared-hosts."photos";
        transmit.port = 8080;
      })
      ({
        description = "Proxy <-> SSO";
        listen.vsock.cid = -1;
        listen.port = 10001;
        transmit.vsock.cid = cid-shared-hosts."sso";
        transmit.port = 8443;
      })
    ];

  microvm.vms."proxy" =
    let
      parent-hostname = config.networking.hostName;
      guest-ssh-key = config.sops.secrets."proxy-vm/ssh_host_ed25519_key".path;
      alpha-certificate-path = config.security.acme.certs."alpha.proesmans.eu".directory;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake special; };

      config = { config, special, ... }: {
        _file = ./proxy-vm.nix;
        imports = [
          special.profiles.qemu-guest-vm
          (meta-module "proxy")
          ../proxy.nix # VM config
        ];

        config = {
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;
          # ERROR; Number must be unique for each VM!
          # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
          microvm.vsock.cid = 3000;

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
            id = "vmac-proxy";
            mac = "52:0d:da:28:b9:5b"; # randomly generated
          }];

          microvm.suitcase.secrets = {
            "ssh_host_ed25519_key".source = guest-ssh-key;
            # Available at "/run/in-secrets-microvm/certificates"
            "certificates".source = alpha-certificate-path;
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
