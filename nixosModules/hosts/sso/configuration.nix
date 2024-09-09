{ pkgs, config, ... }: {

  imports = [
    ./provision.nix # Setup users/groups/applications
  ];

  config = {
    networking.domain = "alpha.proesmans.eu";

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
        LoadCredential = [
          # WARN; Certificate files must be loaded into the unit credential store because
          # the original files require root access. This unit executes with user kanidm permissions.
          "FULLCHAIN_PEM:${config.microvm.suitcase.secrets."certificates".path}/fullchain.pem"
          "KEY_PEM:${config.microvm.suitcase.secrets."certificates".path}/key.pem"
          "IDM_PASS:/seeds/idm_admin_password"
        ];
      };
    };

    # Ignore below
    # Consistent defaults accross all machine configurations.
    system.stateVersion = "24.05";
  };
}
