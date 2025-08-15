{
  lib,
  pkgs,
  config,
  ...
}:
let
  # WARN; kanidm database filepath is fixed and cannot be changed!
  kanidmStatePath = builtins.dirOf config.services.kanidm.serverSettings.db_path;
in
{
  sops.secrets = {
    # NOTE; To initialize the idm_service_desk user (bert-proesmans), login using the idm_admin account and generate a password
    # reset tokens using;
    # 1. kanidm login -D idm_admin
    # 2. kanidm person credential create-reset-token bert.proesmans --name idm_admin
    idm_admin-password.owner = "kanidm";

    # Hold additional personal data.
    kanidm-extra = {
      owner = "kanidm";
      restartUnits = [ config.systemd.services.kanidm.name ];
      # WARN; The json structure leaks personal information!
      # The whole json file is encrypted, instead of only json values.
      format = "binary";
      sopsFile = ./kanidm-extra.encrypted.json;
      # EXAMPLE;
      # {
      #   "persons": {
      #     "<username>": {
      #       "displayName": "<name>",
      #       "groups": [ "<name>" ],
      #       "legalName": null,
      #       "mailAddresses": [ "<email>" ],
      #       "present": true
      #     }
      # }
    };

    immich-oauth-secret = {
      # ERROR; Immich does not properly URL-encode oauth secret value!
      # WORKAROUND; Value must be generated using command:
      #   tr --complement --delete 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkpqrstuvwxyz0123456789' < /dev/urandom | head --bytes 48
      owner = "kanidm";
      restartUnits = [ config.systemd.services.kanidm.name ];
    };
  };

  # Allow kanidm user access to the idm certificate managed by the host
  security.acme.certs."idm.proesmans.eu" = {
    reloadServices = [ config.systemd.services.kanidm.name ];
  };
  users.groups.idm-certs.members = [ "kanidm" ];

  disko.devices.zpool.storage.datasets."sqlite/kanidm" = {
    type = "zfs_fs";
    # WARN; To be backed up !
    options.mountpoint = kanidmStatePath;
  };

  networking.hosts = {
    # Redirect Kanidm traffic to frontend proxy for provisioning
    "127.0.0.1" = [ (lib.removePrefix "https://" config.services.kanidm.serverSettings.origin) ];
  };

  services.kanidm = {
    enableServer = true;
    enableClient = true;
    package = pkgs.kanidm_1_7.withSecretProvisioning;

    # WARN; Setting http_client_address_info requires settings format version 2+
    serverSettings.version = "2";
    serverSettings = {
      bindaddress = "127.204.0.1:8443";
      # HostName; alpha.idm.proesmans.eu
      origin = "https://alpha.idm.proesmans.eu";
      domain = "idm.proesmans.eu";
      db_fs_type = "zfs"; # Changes page size to 64K
      role = "WriteReplica";
      # log_level = "debug";
      online_backup.enabled = false;
      # Accept proxy protocol from frontend stream handler
      http_client_address_info.proxy-v2 = [ "127.0.0.0/8" ];

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

      extraJsonFile = config.sops.secrets.kanidm-extra.path;
      autoRemove = true;
      groups = {
        "idm_service_desk" = { }; # Builtin
        "household.alpha" = { };
        "household.beta" = { };

        "immich.access" = { };
        "immich.admin" = { };
        "immich.quota.large" = { };
      };
      persons."bert.proesmans" = {
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
        # RS256 is used instead of ES256 so additionally we need legacy crypto
        enableLegacyCrypto = true;
        scopeMaps."immich.access" = [
          "openid"
          "email"
          "profile"
        ];
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

  systemd.services.kanidm = {
    wants = [ "acme-finished-idm.proesmans.eu.target" ];
    after = [
      "acme-selfsigned-idm.proesmans.eu.service"
      "acme-idm.proesmans.eu.service"
    ];

    unitConfig.RequiresMountsFor = [
      kanidmStatePath
    ];
  };
}
