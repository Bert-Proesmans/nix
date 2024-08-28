{ ... }: {

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


}
