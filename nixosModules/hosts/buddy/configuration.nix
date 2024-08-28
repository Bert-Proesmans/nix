{ modulesPath, lib, pkgs, config, profiles, ... }: {

  imports = [
    "${modulesPath}/hardware/video/radeon.nix" # AMD Vega GPU (Radeon = pre-amdgpu)
    profiles.server
    profiles.hypervisor
    profiles.dns-server
    ./hardware-configuration.nix
    ./disks.nix
  ];

  networking.hostName = "buddy";
  networking.domain = "alpha.proesmans.eu";

  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.home-manager.enable = true;

  # Make me a user!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Networking configuration
  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;

  # Keep dmesg/journalctl -k output readable by NOT logging
  # each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;

  # Use networkd instead of the pile of shell scripts
  networking.useNetworkd = true;
  # Setup a fixed mac-address on the hypervisor bridge
  systemd.network.netdevs."bridge0" = {
    # ERROR; Must copy in all netdevConfig attribute names because this type of set doesn't merge
    # with other declarations!
    netdevConfig = {
      Name = "bridge0";
      Kind = "bridge";
      MACAddress = "4a:5c:7c:d1:8a:35";
    };
  };
  systemd.network.networks = {
    # Attach the physical interface to the bridge. This allows network access to the VMs
    "30-lan" = {
      matchConfig.MACAddress = [ "b4:2e:99:15:33:a6" ];
      networkConfig = {
        Bridge = "bridge0";
      };
    };
    # The host IP comes from a DHCP offer, the DHCP client must run on/from the bridge interface
    "30-lan-bridge" = {
      matchConfig.Name = "bridge0";
      networkConfig = {
        Address = [ "192.168.100.2/24" ];
        # Gateway = "192.168.100.1";
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
    };
  };

  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  sops.secrets.ssh_host_ed25519_key = {
    path = "/etc/ssh/ssh_host_ed25519_key";
    owner = config.users.users.root.name;
    group = config.users.users.root.group;
    mode = "0400";
    restartUnits = [ config.systemd.services.sshd.name ];
  };

  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  sops.secrets."technitium-vm/ssh_host_ed25519_key" = {
    mode = "0400";
  };

  sops.secrets."cloudflare-proesmans-key" = { };
  sops.secrets."cloudflare-zones-key" = { };
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "bproesmans@hotmail.com";
      dnsProvider = "cloudflare";
      credentialFiles."CLOUDFLARE_DNS_API_TOKEN_FILE" = config.sops.secrets."cloudflare-proesmans-key".path;
      credentialFiles."CLOUDFLARE_ZONE_API_TOKEN_FILE" = config.sops.secrets."cloudflare-zones-key".path;

      # ERROR; The system resolver is very likely to implement a split-horizon DNS.
      # NOTE; Lego uses DNS requests within the certificate workflow. It must use an external DNS directly since
      # all verification uses external DNS records.
      dnsResolver = "1.1.1.1:53";
    };

    certs."idm.proesmans.eu" = {
      # This block requests a wildcard certificate.
      domain = "*.idm.proesmans.eu";

      # WARN; Currently no mechanism to reload services inside the vm directly.
      # TODO
      reloadServices = [ "microvm@kanidm.service" ];
    };
  };

  systemd.services."symlink-certificate-idm.proesmans.eu" = {
    description = "Symlinks the certificate directory to be owned by root, used for virtiofs mounting";
    requiredBy = [ "acme-finished-idm.proesmans.eu.target" ];
    before = [ "acme-finished-idm.proesmans.eu.target" ];

    serviceConfig.Type = "oneshot";
    # Squash permissions for 1:1 mapping into vm through virtiofs
    # WARN; Mount path /var/lib/microvms/kanidm/certs into the vm!
    #
    # REF; https://gitlab.com/virtio-fs/virtiofsd/-/issues/152#note_2005451839
    #
    # OR Not required anymore when virtiofsd gets updated with internal UID/GID mapping (host-side)!
    # REF; https://gitlab.com/virtio-fs/virtiofsd/-/merge_requests/237
    # OR Not required anymore when virtiofsd gets updated for mount UID/GID mapping (vm-side)!
    # REF; https://gitlab.com/virtio-fs/virtiofsd/-/merge_requests/245
    serviceConfig.ExecStart =
      let
        script = pkgs.writeShellApplication {
          name = "squash-permission-mount-certs";
          runtimeInputs = [ pkgs.util-linux ];
          text = ''
            destination="/var/lib/microvms/kanidm/certs"

            certdir="/var/lib/acme/idm.proesmans.eu"
            owner=$(stat -c '%U' "$certdir")
            owner_uid=$(id -u "$owner")

            if [ -e "$destination" ]; then
                if [ -d "$destination" ]; then
                    echo "$destination is a directory."
                else                      
                    if mountpoint -q "$destination"; then
                        echo "$destination is a mount point. Unmounting..."
                        umount "$destination"
                    else
                        echo "$destination is a special node. Attempting to unmount..."
                        umount "$destination" || echo "Failed to unmount $destination. It might not be a mount point."
                    fi
                fi
            fi

            if [ ! -d "$destination" ]; then
              echo "Creating directory $destination..."
              mkdir --parents "$destination"
            fi

            # Certdir is mounted at destination with permissions remapped from original owner to root
            mount -o bind,ro,X-mount.idmap=u:"$owner_uid":0:1 "$certdir" "$destination"
          '';
        };
      in
      lib.getExe script;
  };

  systemd.targets."microvms" = {
    wants = [ "acme-finished-idm.proesmans.eu.target" ];
    after = [ "acme-finished-idm.proesmans.eu.target" ];
  };

  # MicroVM has un-nix-like default of true for enable option, so we need to force it on here.
  microvm.host.enable = lib.mkForce true;

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}

