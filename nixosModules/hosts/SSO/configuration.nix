{ lib, pkgs, config, ... }: {

  imports = [
    ./provision.nix # Setup users/groups/applications
  ];

  config = {
    networking.domain = "alpha.proesmans.eu";

    services.openssh.hostKeys = [
      {
        path = "/data/seeds/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    systemd.services.sshd.unitConfig.ConditionPathExists = "/data/seeds/ssh_host_ed25519_key";

    # DEBUG
    security.sudo.enable = true;
    security.sudo.wheelNeedsPassword = false;
    users.users.bert-proesmans.extraGroups = [ "wheel" ];
    # DEBUG

    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = [ 443 ];

    environment.systemPackages = [
      # Add CLI tools to PATH
      pkgs.kanidm
    ];

    # ERROR; Kanidm database path option is readonly and cannot be changed!
    #
    # Alternative, set /var/lib/kanidm to a symlink. This requires to mimic service config
    # StateDirectory manually; create directory out of tree, update permissions + symlink into /var/lib
    #
    # WARN; Disable StateDirectory from the systemd service unit.
    systemd.tmpfiles.settings."20-kanidm" = {
      # Adjust permissions of files within the state directory
      "/data/state".Z = {
        user = "kanidm";
        group = "kanidm";
        mode = "0700";
      };

      "/var/lib/kanidm".L.argument = "/data/state";
    };

    services.kanidm = {
      enableServer = true;
      # NOTE; Custom patches required to pre-provision secret values like;
      #   - admin account passwords
      #   - oauth2 basic secrets
      package = pkgs.kanidm.withSecretProvisioning;
      serverSettings = {
        bindaddress = "0.0.0.0:443"; # Requires CAP_NET_BIND_SERVICE
        domain = "idm.proesmans.eu";
        origin = "https://idm.proesmans.eu";
        # ERROR; Cannot change database path
        #db_path = "/data/state/kanidm.db";
        db_fs_type = "zfs"; # Changes page size to 64K
        role = "WriteReplica";
        online_backup.enabled = false;

        # Path prefix '/run/credentials/<unit name>/' is expanded value of '%d' and
        # '$CREDENTIALS_DIRECTORY' aka SystemD credentials directory.
        # SEEALSO; systemd.services.kanidm.serviceConfig.LoadCredential`
        #
        # NOTE; These certificate paths are automatically added as read-only bind paths
        # by the upstream nixos module. The binding doesn't seem to have any impact on
        # the credentials infrastructure.
        tls_chain = "/run/credentials/kanidm.service/FULLCHAIN_PEM";
        tls_key = "/run/credentials/kanidm.service/KEY_PEM";
      };

      provision.idmAdminPasswordFile = "/run/credentials/kanidm.service/IDM_PASS";
    };

    systemd.services.kanidm = {
      serviceConfig = {
        # /var/lib/kanidm is a symlink so don't create the state directory
        StateDirectory = lib.mkForce "";
        BindPaths = [
          # Allow the service to see the symlink, but also the state directory it points to
          "/var/lib/kanidm"
          "/data/state"
        ];
        LoadCredential = [
          # WARN; Certificate files must be loaded into the unit credential store because
          # the original files require root access. This unit executes with user kanidm permissions.
          "FULLCHAIN_PEM:/data/certs/fullchain.pem"
          "KEY_PEM:/data/certs/key.pem"
          "IDM_PASS:/data/seeds/idm_admin_password"
        ];
      };
    };

    # Ignore below
    # Consistent defaults accross all machine configurations.
    system.stateVersion = "24.05";
  };
}
