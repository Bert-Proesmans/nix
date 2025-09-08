{
  pkgs,
  config,
  flake,
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

    outline-oauth-secret = {
      owner = "kanidm";
      restartUnits = [ config.systemd.services.kanidm.name ];
    };
  };

  # Allow kanidm user access to the idm certificate managed by the host
  security.acme.certs."alpha.idm.proesmans.eu" = {
    reloadServices = [ config.systemd.services.kanidm.name ];
    group = "kanidm";
  };

  disko.devices.zpool.storage.datasets."sqlite/kanidm" = {
    type = "zfs_fs";
    # WARN; To be backed up !
    options.mountpoint = kanidmStatePath;
    options.refquota = "1G";
  };

  networking.hosts = {
    # Redirect Kanidm traffic to frontend proxy for provisioning
    "127.0.0.1" = [
      "idm.proesmans.eu"
      "alpha.idm.proesmans.eu"
    ];
  };

  services.kanidm = {
    enableServer = true;
    enableClient = true;
    package = pkgs.kanidm_1_7.withSecretProvisioning;

    # WARN; Setting http_client_address_info requires settings format version 2+
    serverSettings.version = "2";
    serverSettings = {
      bindaddress = "127.204.0.1:8443";
      # HostName; alpha.idm.proesmans.eu, beta.idm.proesmans.eu ...
      # ERROR; These hostnames cannot be used as web resources under the openid specification
      # NOTE; These hostnames can be used as web resources under the webauthn+cookies specification
      #
      # HELP; Domain and origin must be the same for all regional instances of IDM.
      domain = "idm.proesmans.eu";
      origin = "https://idm.proesmans.eu";
      db_fs_type = "zfs"; # Changes page size to 64K
      role = "WriteReplica";
      # log_level = "debug";
      online_backup.enabled = false;
      # Accept proxy protocol from frontend stream handler
      http_client_address_info.proxy-v2 = [ "127.0.0.0/8" ];

      tls_chain = config.security.acme.certs."alpha.idm.proesmans.eu".directory + "/fullchain.pem";
      tls_key = config.security.acme.certs."alpha.idm.proesmans.eu".directory + "/key.pem";
    };

    clientSettings = {
      # ERROR; MUST MATCH _instance_ DNS hostname exactly due to certificate validation!
      uri = "https://alpha.idm.proesmans.eu";
      verify_hostnames = true;
      verify_ca = true;
    };

    provision = {
      enable = true;
      # ERROR; MUST MATCH _instance_ DNS hostname exactly due to certificate validation!
      instanceUrl = "https://alpha.idm.proesmans.eu";
      idmAdminPasswordFile = config.sops.secrets.idm_admin-password.path;
      acceptInvalidCerts = false;

      # TODO; Change logo and name if/when provisioning is supported
      # REF; https://github.com/oddlama/kanidm-provision/issues/30

      extraJsonFile = config.sops.secrets.kanidm-extra.path;
      autoRemove = true;
      groups = {
        "idm_service_desk" = { }; # Builtin
        "household.alpha" = { };
        "household.beta" = { };

        "immich.access" = { };
        "immich.admin" = { };
        "immich.quota.large" = { };
        "outline.access" = { };
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
          "outline.access"
        ];
      };

      systems.oauth2."photos" = {
        displayName = "Pictures";
        basicSecretFile = config.sops.secrets.immich-oauth-secret.path;
        # WARN; URLs must end with a forward slash if path element is empty!
        originLanding = "https://pictures.proesmans.eu/";
        imageFile = "${flake.documentationAssets}/immich-logo.png";
        originUrl = [
          # NOTE; Global url redirects to specific instance URLs
          "https://pictures.proesmans.eu/auth/login"
          "https://alpha.pictures.proesmans.eu/auth/login"
          "https://omega.pictures.proesmans.eu/auth/login"
          "app.immich:///oauth-callback" # "app.immich:///" (??)

          # If unlinking/relinking oauth ids are allowed
          # "https://pictures.proesmans.eu/user-settings"
          # "https://alpha.pictures.proesmans.eu/user-settings"
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

      systems.oauth2."wiki" = {
        displayName = "Wiki";
        basicSecretFile = config.sops.secrets.outline-oauth-secret.path;
        # WARN; URLs must end with a forward slash if path element is empty!
        originLanding = "https://wiki.proesmans.eu/";
        # imageFile = "<TODO>";
        originUrl = [
          # NOTE; Global url redirects to specific instance URLs
          "https://wiki.proesmans.eu/auth/oidc.callback"
          "https://alpha.wiki.proesmans.eu/auth/oidc.callback"
          "https://omega.wiki.proesmans.eu/auth/oidc.callback"
        ];
        scopeMaps."outline.access" = [
          "openid"
          "email"
          "profile"
        ];
      };
    };
  };

  systemd.services.kanidm = {
    requires = [ "acme-alpha.idm.proesmans.eu.service" ];
    after = [
      "acme-alpha.idm.proesmans.eu.service"
      # Provisioning is rerouted through proxy for certificate validation
      config.systemd.services.haproxy.name
    ];

    unitConfig.RequiresMountsFor = [
      kanidmStatePath
    ];
  };
}
