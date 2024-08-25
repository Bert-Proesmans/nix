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

  # Leave ZFS pool alone!
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Tune ZFS
  #
  # NOTE; Not tackling limited free space performance impact. Due to the usage of AVL trees to track free space,
  # a highly fragmented or simply a full pool results in more overhead to find free space. There is actually no
  # robust solution for this problem, there is no quick or slow fix (defragmentation). Your pool should be sized
  # at maximum required space +- ~10% from the beginning.
  # If your pool is full => expand it by a large amount. If your pool is fragmented => create a new dataset and
  # move your data out of the old dataset + purge old dataset + move back into the new dataset.
  #
  # HELP; A way to solve used space performance impact is to set dataset quota's to limit space usage to ~90%.
  # With a 90% usage limit there is backpressure to cleanup earlier snapshots. Doesn't work if your pool is
  # full though!
  boot.extraModprobeConfig = ''
    # Fix the commit timeout (seconds), because the default has changed before
    options zfs zfs_txg_timeout=5

    # This is a hypervisor server, and ZFS ARC is sometimes slow with giving back RAM.
    # It defaults to 50% of total RAM, but we fix it to 8 GiB (bytes)
    options zfs zfs_arc_max=8589934592

    # Data writes less than this amount (bytes) are written in sync, while writes larger are written async.
    # WARN; Only has effect when no SLOG special device is attached to the pool to be written to.
    #
    # ERROR; Data writes larger than the recordsize are automatically async, to prevent complexities while handling
    # multiple block pointers in a ZIL log record.
    # Set this value equal to or less than the largest recordsize written on this system/pool. (bytes?)
    options zfs zfs_immediate_write_sz=1048576

    # Enable prefetcher. Zfs proactively reads data from spinning disks, expecting inflight or future requests, into
    # the ARC.
    options zfs zfs_prefetch_disable=0
  '';

  services.fstrim.enable = true;
  services.zfs.trim.enable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "weekly";

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
      MACAddress = lib.facts.buddy.net.management.mac;
    };
  };
  systemd.network.networks = {
    # Attach the physical interface to the bridge. This allows network access to the VMs
    "30-lan" = {
      matchConfig.MACAddress = [ lib.facts.buddy.net.physical.mac ];
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

  # The notion of "online" is a broken concept
  # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;

  # FIXME: Maybe upstream?
  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping it with `systemctl stop`
  # followed by a delayed `systemctl start`.
  systemd.services.systemd-networkd.stopIfChanged = false;
  # Services that are only restarted might be not able to resolve when resolved is stopped before
  systemd.services.systemd-resolved.stopIfChanged = false;

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
  sops.secrets."kanidm-vm/ssh_host_ed25519_key" = {
    mode = "0400";
  };

  sops.secrets."cloudflare-proesmans-key" = { };
  sops.secrets."cloudflare-zones-key" = { };
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = lib.facts.acme.email;
      dnsProvider = "cloudflare";
      credentialFiles."CLOUDFLARE_DNS_API_TOKEN_FILE" = config.sops.secrets."cloudflare-proesmans-key".path;
      credentialFiles."CLOUDFLARE_ZONE_API_TOKEN_FILE" = config.sops.secrets."cloudflare-zones-key".path;

      # ERROR; Lego uses DNS requests within the certificate workflow. It must use an external DNS directly since
      # all validation uses external DNS records.
      # NOTE; The system resolver is very likely to implement a split-horizon DNS.
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
  microvm.vms = {
    kanidm = {
      autostart = true;
      specialArgs = { inherit profiles; };

      # The configuration for the MicroVM.
      # Multiple definitions will be merged as expected.
      config = { config, ... }: {
        # ERROR; Number must be unique for each VM!
        # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
        microvm.vsock.cid = lib.facts.vm.idm.vsock-id;
        networking.hostName = "SSO";
        imports = [ profiles.micro-vm ];

        microvm.interfaces = [{
          type = "tap";
          id = "tap-kanidm";
          mac = lib.facts.vm.idm.net.mac;
        }];

        microvm.shares = [
          {
            source = "/run/secrets/kanidm-vm";
            mountPoint = "/seeds";
            tag = "container_kanidm";
            proto = "virtiofs";
          }
          {
            source = "/vm/kanidm";
            mountPoint = "/data/state";
            tag = "state-kanidm";
            proto = "virtiofs";
          }
          {
            source = "/var/lib/microvms/kanidm/certs";
            mountPoint = "/data/certs";
            tag = "certs-kanidm";
            proto = "virtiofs";
          }
        ];

        services.openssh.hostKeys = [
          {
            path = "/seeds/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
        systemd.services.sshd.unitConfig.ConditionPathExists = "/seeds/ssh_host_ed25519_key";

        # DEBUG
        security.sudo.enable = true;
        security.sudo.wheelNeedsPassword = false;
        users.users.bert-proesmans.extraGroups = [ "wheel" ];
        # DEBUG

        networking.firewall.enable = true;
        networking.firewall.allowedTCPPorts = [ 443 ];

        services.kanidm = {
          enableServer = true;
          serverSettings = {
            bindaddress = "0.0.0.0:443"; # Requires CAP_NET_BIND_SERVICE
            domain = "idm.proesmans.eu";
            origin = "https://idm.proesmans.eu";
            # Customized because a lack of permissions
            tls_chain = "/run/data/certs/fullchain.pem";
            tls_key = "/run/data/certs/key.pem";
            db_fs_type = "zfs";
            role = "WriteReplica";
            online_backup.versions = 0; # disable online backup
          };
        };

        # NOTE; Assign /run/data/certs as certdir
        systemd.tmpfiles.rules = [
          "d /run/data                0700 root   root    - -"
          "d /run/data/certs          0700 kanidm kanidm  - -"
        ];
        systemd.services.kanidm.serviceConfig = {
          # AmbientCapabilities = [ "NET_BIND_SERVICE" ];
          # CapabilityBoundingSet = [ "NET_BIND_SERVICE" ];
          # /data/state (root-owned) -> /var/lib/kanidm-mount (bind as-is) 
          # -> /var/lib/kanidm-mount/rw-data (+ rw dir rw-data) -> /var/lib/kanidm (symlink to rw-data)
          StateDirectory = [
            # NOTE; Use systemd's permission skip ability to create a rw-folder inside the root-owned
            # virtiofs mount.
            "kanidm-mount/rw-data:/var/lib/kanidm"
          ];
          BindPaths = [
            "/data/state:/var/lib/kanidm-mount"
          ];
        };
        systemd.services."kanidm-secrets-init" = {
          description = "Copies over secrets for the kanidm service";
          wantedBy = [ config.systemd.services.kanidm.name ];
          before = [ config.systemd.services.kanidm.name ];

          unitConfig.ConditionPathExists = "/data/certs/fullchain.pem";
          serviceConfig.Type = "oneshot";
          # /data/certs (root-owned) -> /run/kanidm/certs (file copy) -> chown kanidm
          # RuntimeDirectory = [
          #   "kanidm/certs" # Assign /run/kanidm/certs as certdir
          # ];
          # NOTE; Assign /run/data/certs as certdir
          serviceConfig.ExecStart =
            let
              script = pkgs.writeShellApplication {
                name = "copy-kanidm-certs";
                runtimeInputs = [ ];
                text = ''
                  source="/data/certs"
                  destination="/run/data/certs" 

                  (umask 077; cp "$source"/*.pem "$destination"/)
                  chown kanidm:kanidm "$destination"/*.pem
                '';
              };
            in
            lib.getExe script;
        };

      };
    };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}

