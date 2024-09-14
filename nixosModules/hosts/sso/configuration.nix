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

    nixpkgs.overlays = [
      (_: prev: {
        # Lightweight build of kanidm (only daemon) so it doesn't break my groove for hours ... ~10 minutes
        # NOTE; kanidm is marked for "big-parallel" builders
        #
        # NOTE; Have to rebuild anyway because we need secret provisioning, this variant is not built/cached
        # by hydra.
        kanidm-daemon-slim = (prev.kanidm.withSecretProvisioning).overrideAttrs (prevAttrs: {
          # Only build daemon
          buildAndTestSubdir = "server/daemon";
          # Skip testing, assuming upstream has built and tested the complete package
          doCheck = false;
          # Clear preFixup because it does stuff for other programs
          preFixup = "";
          # Mark the main program, so unsock.wrap works
          meta.mainProgram = "kanidmd";
        });
      })
    ];

    services.kanidm = {
      enableServer = true;
      # NOTE; Custom patches required to pre-provision secret values like;
      #   - admin account passwords
      #   - oauth2 basic secrets
      package = pkgs.kanidm-daemon-slim;
      serverSettings = {
        bindaddress = "127.175.0.0:8443";
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

      provision.instanceUrl = "https://127.175.0.0:8443";
      provision.acceptInvalidCerts = true; # Certificate won't validate IP address
      provision.idmAdminPasswordFile = "/run/credentials/kanidm.service/IDM_PASS";
      provision.systems.oauth2."photos".basicSecretFile = "/run/credentials/kanidm.service/IMMICH_OAUTH2";
    };

    systemd.services.kanidm = {
      serviceConfig = {
        LoadCredential = [
          # WARN; Certificate files must be loaded into the unit credential store because
          # the original files require root access. This unit executes with user kanidm permissions.
          "FULLCHAIN_PEM:${config.microvm.suitcase.secrets."certificates".path}/fullchain.pem"
          "KEY_PEM:${config.microvm.suitcase.secrets."certificates".path}/key.pem"
          "IDM_PASS:${config.microvm.suitcase.secrets."secrets".path}/idm_admin_password"
          "IMMICH_OAUTH2:${config.microvm.suitcase.secrets."secrets".path}/openid-secret-immich"
        ];
      };
    };

    # NOTE; kanidm-provision uses hardcoded curl that we cannot individually wrap into unsock.
    # So the second best approach is a dedicated VSOCK proxy service.
    proesmans.vsock-proxy.proxies = [{
      description = "Connect VSOCK to AF_INET for kanidm service";
      listen.vsock.cid = -1; # Binds to guest localhost
      listen.port = 8443;
      transmit.tcp.ip = "127.175.0.0";
      transmit.port = 8443;
    }];

    # Ignore below
    # Consistent defaults accross all machine configurations.
    system.stateVersion = "24.05";
  };
}
