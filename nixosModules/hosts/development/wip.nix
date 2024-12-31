{ lib, pkgs, config, ... }:
let
  json-convert = pkgs.formats.json { };
in
{
  sops.secrets.test-secret = {
    owner = "kanidm"; # DEBUG
  };
  sops.templates."immich-config.json" = {
    file = json-convert.generate "immich.json" config.services.immich.settings;
    owner = "immich";
    restartUnits = [ config.systemd.services.immich-server.name ];
  };

  services.immich = {
    enable = true;
    host = "127.175.0.1";
    port = 8080;
    openFirewall = false; # Use reverse proxy

    database = {
      enable = true;
      name = "immich";
      createDB = true;
    };

    settings = {
      backup.database.enabled = false;
      ffmpeg = {
        accel = "disabled";
        acceptedAudioCodecs = [ "aac" "libopus" ];
        acceptedVideoCodecs = [ "h264" "av1" ];
      };
      image.preview.size = 1080;
      library.scan.cronExpression = "0 2 * * 1";
      library.scan.enabled = true;
      logging.enabled = true;
      logging.level = "log";
      machineLearning.facialRecognition = {
        enabled = true;
        maxDistance = 0.45;
        minFaces = 5;
      };
      machineLearning.urls = [ "http://127.175.0.99:3003" ];
      map.darkStyle = "https://tiles.immich.cloud/v1/style/dark.json";
      map.enabled = true;
      map.lightStyle = "https://tiles.immich.cloud/v1/style/light.json";
      newVersionCheck.enabled = false;
      notifications.smtp.enabled = false;
      oauth = {
        enabled = false; # TODO
        autoRegister = true;
        buttonText = "Login with proesmans account";
        clientId = "<TODO>";
        clientSecret = config.sops.placeholder.test-secret;
        defaultStorageQuota = 200;
        issuerUrl = "https://idm.proesmans.eu/oauth2/openid/<TODO clientId>";
        mobileOverrideEnabled = false;
        mobileRedirectUri = "";
        profileSigningAlgorithm = "none";
        scope = "openid email profile";
        signingAlgorithm = "RS256";
        storageLabelClaim = "preferred_username";
        storageQuotaClaim = "immich_quota";
      };
      passwordLogin.enabled = true;
      reverseGeocoding.enabled = true;
      server.externalDomain = "https://photos.alpha.proesmans.eu";
      server.loginPageMessage = "Proesmans Photos";
      server.publicUsers = true;
      storageTemplate.enabled = true;
      # 2024/2024-12[-06][ Sinterklaas]/IMG_001.jpg
      storageTemplate.template = "{{y}}/{{y}}-{{MM}}{{#if dd}}-{{dd}}{{else}}{{/if}}{{#if album}} {{{album}}}{{else}}{{/if}}/{{{filename}}}";
      trash.days = 200;
      trash.enabled = true;
      user.deleteDelay = 30;
    };

    environment = {
      TZ = "Europe/Brussels"; # Used for interpreting timestamps without time zone
    };

    machine-learning = {
      enable = true;
      environment = {
        IMMICH_HOST = lib.mkForce "127.175.0.99"; # Upstream overwrite
        IMMICH_PORT = lib.mkForce "3003"; # Upstream overwrite
        MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
        # Redirect temporary files to disk-backed temporary folder.
        TMPDIR = "/var/tmp";
      };
    };
  };

  systemd.services.immich-server = {
    environment.IMMICH_CONFIG_FILE = lib.mkForce config.sops.templates."immich-config.json".path;
  };

  # Disables ACME cert generation from external party. (Keep self-signed certs intact)
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "invalid";
  security.acme.certs."idm.proesmans.eu" = {
    # This block requests a wildcard certificate.
    domain = "*.idm.proesmans.eu";
    dnsProvider = "invalid";
    group = "nginx";
    reloadServices = [ config.systemd.services."kanidm".name ];
  };

  # NOTE; (Brittle) effectively disable external ACME requests to make use of selfsigned certs
  systemd.services."acme-idm.proesmans.eu".serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    enable = true;
    virtualHosts."alpha.idm.proesmans.eu" = {
      # Use the generated wildcard certificate, see security.acme.certs.<name>
      useACMEHost = "idm.proesmans.eu";
      forceSSL = true;
      locations."/" = {
        proxyPass = "https://127.204.0.1:8443";
        proxyWebsockets = true;
      };
    };
  };

  systemd.services.kanidm.serviceConfig.Group = lib.mkForce "nginx"; # DEBUG

  services.kanidm = {
    package = pkgs.kanidm_1_4.withSecretProvisioning;
    enableServer = true;
    serverSettings = {
      bindaddress = "127.204.0.1:8443";
      # HostName; alpha.idm.proesmans.eu
      origin = "https://idm.proesmans.eu";
      domain = "idm.proesmans.eu";
      db_fs_type = "zfs"; # Changes page size to 64K
      role = "WriteReplica";
      online_backup.enabled = false;

      tls_chain = config.security.acme.certs."idm.proesmans.eu".directory + "/fullchain.pem";
      tls_key = config.security.acme.certs."idm.proesmans.eu".directory + "/key.pem";
    };

    provision = {
      enable = true;
      instanceUrl = "https://127.204.0.1:8443";
      # ERROR; Certificate is bound to DNS name won't validate IP address
      acceptInvalidCerts = true;
      idmAdminPasswordFile = config.sops.secrets.test-secret.path;
      autoRemove = true;
      groups = {
        "idm_service_desk" = { }; # Builtin
        "alpha" = { };

        "immich.access" = { };
        "immich.admin" = { };
      };
      persons."bert-proesmans" = {
        displayName = "Bert Proesmans";
        mailAddresses = [ "bert@proesmans.eu" ];
        groups = [
          # Allow credential reset on other persons
          "idm_service_desk" # tainted role
          "alpha"
          "immich.access"
          "immich.admin"
        ];
      };

      systems.oauth2."photos" = {
        displayName = "Immich SSO";
        basicSecretFile = config.sops.secrets.test-secret.path;
        # basicSecretFile = "See configuration.nix";
        # WARN; URLs must end with a forward slash if path element is empty!
        originLanding = "https://photos.alpha.proesmans.eu/";
        originUrl = [
          # WARN; Overly strict origin url requirement I think :/
          #
          #"https://photos.alpha.proesmans.eu/auth/login"
          "https://photos.alpha.proesmans.eu/"
          #"app.immich:///oauth-callback"
          "app.immich:///"
        ];
        scopeMaps."immich.access" = [ "openid" "email" "profile" ];
        preferShortUsername = true;
        # PKCE is currently not supported by immich
        allowInsecureClientDisablePkce = true;
        # RS256 is used instead of ES256 so additionally we need legacy crypto
        enableLegacyCrypto = true;
      };
    };
  };
}
