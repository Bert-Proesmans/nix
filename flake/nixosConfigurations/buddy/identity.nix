{ lib, pkgs, config, ... }:
let
  # WARN; kanidm database filepath is fixed and cannot be changed!
  kanidmStatePath = builtins.dirOf config.services.kanidm.serverSettings.db_path;
in
{
  sops.secrets = {
    idm_admin-password.owner = "kanidm";
    immich-oauth-secret = {
      # ERROR; Immich does not properly URL-encode oauth secret value!
      # WORKAROUND; Value must be generated using command:
      #   tr --complement --delete 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkpqrstuvwxyz0123456789' < /dev/urandom | head --bytes 48
      owner = "kanidm";
      restartUnits = [ config.systemd.services.kanidm.name ];
    };
  };

  security.acme.certs."idm.proesmans.eu" = {
    reloadServices = [ config.systemd.services.kanidm.name ];
  };
  users.groups.idm-certs.members = [ "kanidm" ];
  systemd.services.kanidm = {
    wants = [ "acme-finished-idm.proesmans.eu.target" ];
    after = [ "acme-selfsigned-idm.proesmans.eu.service" "acme-idm.proesmans.eu.service" ];
    serviceConfig.RuntimeDirectory = [ "kanidm" ];
  };

  disko.devices.zpool.storage.datasets."sqlite/kanidm" = {
    type = "zfs_fs";
    # WARN; To be backed up !
    options.mountpoint = kanidmStatePath;
  };

  # Redirect Kanidm traffic to nginx proxy
  networking.extraHosts = ''
    127.0.0.1 ${lib.removePrefix "https://" config.services.kanidm.serverSettings.origin}
  '';

  services.kanidm = {
    enableServer = true;
    enableClient = true;
    package = pkgs.kanidm_1_6.withSecretProvisioning;

    serverSettings = {
      bindaddress = "127.204.0.1:8443";
      # HostName; alpha.idm.proesmans.eu
      origin = "https://alpha.idm.proesmans.eu";
      domain = "idm.proesmans.eu";
      db_fs_type = "zfs"; # Changes page size to 64K
      role = "WriteReplica";
      online_backup.enabled = false;
      trust_x_forward_for = false;
      log_level = "debug";

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
      instanceUrl = config.services.kanidm.serverSettings.origin;
      idmAdminPasswordFile = config.sops.secrets.idm_admin-password.path;
      acceptInvalidCerts = false;

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
            valuesByGroup."immich.quota.large" = [ "1000" ]; # 1000GB storage
          };
        };
      };
    };
  };
}
