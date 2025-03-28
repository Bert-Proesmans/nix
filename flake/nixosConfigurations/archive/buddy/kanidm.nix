# Setup identity management (Idm)
{ pkgs, config, ... }: {
  sops.secrets.idm_admin-password = {
    owner = "kanidm";
  };

  sops.secrets.immich-oauth-secret = {
    # ERROR; Value must be generated using command:
    # tr --complement --delete 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkpqrstuvwxyz0123456789' < /dev/urandom | head --bytes 48
    owner = "kanidm";
    restartUnits = [ config.systemd.services.kanidm.name ];
  };

  security.acme.certs."idm.proesmans.eu" = {
    group = "kanidm";
    reloadServices = [ config.systemd.services."kanidm".name ];
  };

  services.kanidm = {
    enableServer = true;
    enableClient = true;
    package = pkgs.kanidm_1_4.withSecretProvisioning;

    serverSettings = {
      bindaddress = "127.204.0.1:8443";
      # HostName; alpha.idm.proesmans.eu
      origin = "https://alpha.idm.proesmans.eu";
      domain = "idm.proesmans.eu";
      db_fs_type = "zfs"; # Changes page size to 64K
      role = "WriteReplica";
      online_backup.enabled = false;
      trust_x_forward_for = true;

      tls_chain = config.security.acme.certs."idm.proesmans.eu".directory + "/fullchain.pem";
      tls_key = config.security.acme.certs."idm.proesmans.eu".directory + "/key.pem";
    };

    clientSettings = {
      uri = config.services.kanidm.serverSettings.origin;
      verify_hostnames = true;
      verify_ca = true;
    };

    provision = {
      enable = true;
      instanceUrl = "https://${config.services.kanidm.serverSettings.bindaddress}";
      idmAdminPasswordFile = config.sops.secrets.idm_admin-password.path;
      # ERROR; Certificate is bound to DNS name won't validate for IP address
      acceptInvalidCerts = true;

      autoRemove = true;
      groups = {
        "idm_service_desk" = { }; # Builtin
        "household.alpha" = { };
        "household.beta" = { };

        "immich.access" = { };
        "immich.admin" = { };
        "immich.quota.large" = { };
      };
      persons."bert-proesmans" = {
        displayName = "Bert Proesmans";
        mailAddresses = [ "bert@proesmans.eu" ];
        groups = [
          # Allow credential reset on other persons
          "idm_service_desk" # tainted role
          "household.alpha"
          "immich.access"
          "immich.admin"
          "immich.quota.large"
        ];
      };

      systems.oauth2."photos" = {
        displayName = "Immich SSO";
        basicSecretFile = config.sops.secrets.immich-oauth-secret.path;
        # WARN; URLs must end with a forward slash if path element is empty!
        originLanding = "https://photos.alpha.proesmans.eu/";
        originUrl = [
          "https://photos.alpha.proesmans.eu/auth/login"
          "app.immich:///oauth-callback" # "app.immich:///" (??)
        ];
        preferShortUsername = true;
        # PKCE is currently not supported by immich
        allowInsecureClientDisablePkce = true;
        # RS256 is used instead of ES256 so additionally we need legacy crypto
        enableLegacyCrypto = true;
        scopeMaps."immich.access" = [ "openid" "email" "profile" ];
        claimMaps = {
          # NOTE; Immich currently ONLY applies these claims during account creation!
          "immich_label" = {
            joinType = "ssv"; # Immich requires a string type
            valuesByGroup = {
              "household.alpha" = [ "alpha" ]; # storage label "alpha" (organises library location by household)
              "household.beta" = [ "beta" ];
            };
          };
          "immich_quota" = {
            joinType = "ssv"; # Immich requires a string type
            valuesByGroup."immich.quota.large" = [ "500" ]; # 500GB storage
          };
        };
      };
    };
  };
}
