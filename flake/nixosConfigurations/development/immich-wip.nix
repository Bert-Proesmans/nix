{ lib, pkgs, config, ... }:
let
  json-convert = pkgs.formats.json { };
  # Oauth2 secrets must fit certain syntax!
  # tr --complement --delete 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkpqrstuvwxyz0123456789' < /dev/urandom | head --bytes 48
  imm-pass = "SA6X979SfXxaN6g9621qw18eycZC9jawvc2342952pX7xtUb";

  oauth-test-pass = "*XeIF&SPDqcerU&FZ1P!8XWkFAAmgul6";
  #oauth-test-pass = "*XeIFSPDqcerUFZ1P!8XWkFAAmgul6";
in
{
  sops.secrets.test-secret = {
    # DEBUG; Give kanidm access to "a secret" for password provisioning
    # Provisioning secrets should be directly assigned to kanidm
    owner = "kanidm";
  };
  sops.templates."immich-config.json" = {
    file = json-convert.generate "immich.json" config.services.immich.settings;
    owner = "immich";
    restartUnits = [ config.systemd.services.immich-server.name ];
  };

  services.oauth2-proxy = {
    enable = false;
    httpAddress = "http://127.0.0.1:8080";
    tls.enable = false;
    reverseProxy = true;

    provider = "oidc";
    clientID = "test";
    clientSecret = oauth-test-pass;
    scope = "openid profile";
    # "https://alpha.idm.proesmans.eu/oauth2/openid/test/.well-known/openid-configuration"
    oidcIssuerUrl = "https://alpha.idm.proesmans.eu/oauth2/openid/test";
    loginURL = "https://alpha.idm.proesmans.eu/oauth2/authorise";
    redeemURL = "https://alpha.idm.proesmans.eu/oauth2/token";
    validateURL = "https://alpha.idm.proesmans.eu/oauth2/token/introspect";
    profileURL = "https://alpha.idm.proesmans.eu/oauth2/openid/test/userinfo";


    email.domains = [ "*" ];
    # nginx.domain = "auth.alpha.proesmans.eu";
    cookie.secure = true;
    cookie.secret = "oauth-test-pass";
    cookie.httpOnly = false;
    cookie.domain = ".proesmans.eu";

    # OAUTH2_PROXY_CODE_CHALLENGE_METHOD = "S256";
    # OAUTH2_PROXY_COOKIE_CSRF_EXPIRE = "300s";
    # OAUTH2_PROXY_UPSTREAM = "file://opt/index.html";
    # OAUTH2_PROXY_SSL_INSECURE_SKIP_VERIFY = "true";

    # OAUTH2_PROXY_HTTPS_ADDRESS = ":${PROXY_HTTPS_PORT}";
    # OAUTH2_PROXY_TLS_CERT_FILE = "/opt/cert.pem";
    # OAUTH2_PROXY_TLS_KEY_FILE = "/opt/key.pem";
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
        enabled = true; # TODO
        autoRegister = true;
        buttonText = "Login with proesmans account";
        clientId = "photos";
        # clientSecret = config.sops.placeholder.test-secret;
        clientSecret = imm-pass; # DEBUG
        defaultStorageQuota = 100;
        issuerUrl = "https://alpha.idm.proesmans.eu/oauth2/openid/photos/.well-known/openid-configuration";
        mobileOverrideEnabled = false;
        mobileRedirectUri = "";
        profileSigningAlgorithm = "none";
        scope = "openid email profile";
        signingAlgorithm = "RS256";
        # NOTE; Immich currently ONLY applies these claims during account creation!
        storageLabelClaim = "immich_label";
        storageQuotaClaim = "immich_quota";
      };
      passwordLogin.enabled = true;
      reverseGeocoding.enabled = true;
      server.externalDomain = "https://photos.alpha.proesmans.eu";
      server.loginPageMessage = "Proesmans Photos system, proceed by clicking the button at the bottom";
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
    #environment.IMMICH_CONFIG_FILE = lib.mkForce null;
    # DEBUG; Disable self-signed certificate validation.
    # This is a non-issue with publicly issued certificates.
    environment.NODE_TLS_REJECT_UNAUTHORIZED = "0";
  };

  # Disables ACME cert generation from external party. (Keep self-signed certs intact)
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "invalid";
  security.acme.certs."idm.proesmans.eu" = {
    # This block requests a wildcard certificate.
    domain = "*.idm.proesmans.eu";
    dnsProvider = "invalid";
    # DEBUG; Nginx complains because it cannot access the certificate data
    group = "nginx";
    reloadServices = [ config.systemd.services."kanidm".name ];
  };

  security.acme.certs."alpha.proesmans.eu" = {
    # This block requests a wildcard certificate.
    domain = "*.alpha.proesmans.eu";
    dnsProvider = "invalid";
    # DEBUG; Nginx complains because it cannot access the certificate data
    group = "nginx";
  };

  # NOTE; (Brittle) effectively disable external ACME requests to make use of selfsigned certs
  systemd.services."acme-idm.proesmans.eu".serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
  systemd.services."acme-alpha.proesmans.eu".serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    enable = true;
    virtualHosts."auth.alpha.proesmans.eu" = {
      # Use the generated wildcard certificate, see security.acme.certs.<name>
      useACMEHost = "alpha.proesmans.eu";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
      };
    };
    # virtualHosts."photos.alpha.proesmans.eu" = {
    #   # Use the generated wildcard certificate, see security.acme.certs.<name>
    #   useACMEHost = "alpha.proesmans.eu";
    #   forceSSL = true;
    #   locations."/" = {
    #     proxyPass = "http://127.175.0.1:8080";
    #     proxyWebsockets = true;
    #     extraConfig = ''
    #       # Required for larger uploads to be possible (defaults at 10M)
    #       client_max_body_size 500M;
    #     '';
    #   };
    # };
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

  # DEBUG; Access to kanidm self-signed certificates.
  # Certificates should be individually assigned to kanidm and reverse proxy should relay TCP/TLS stream.
  systemd.services.kanidm.serviceConfig.Group = lib.mkForce "nginx";

  environment.systemPackages = [
    (
      # DEBUG; Must point the root certificate set to the dynamically generated ones, otherwise reqwest errors during connect on
      # chain of trust verification failure.
      # This is a non-issue with publicly issued certificates.
      pkgs.symlinkJoin {
        name = "wrapped-kanidm";
        paths = [ config.services.kanidm.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];

        postBuild = ''
          wrapProgram $out/bin/kanidm --set SSL_CERT_FILE "${config.security.acme.certs."idm.proesmans.eu".directory + "/fullchain.pem"}"
        '';
      })
  ];

  # DEBUG; Manual kanidm cli configuration
  environment.etc."kanidm/config".text = ''
    uri = "https://127.204.0.1:8443"
    verify_hostnames = false
    verify_ca = false
    ca_path = "${config.security.acme.certs."idm.proesmans.eu".directory + "/fullchain.pem"}"
  '';
  # DEBUG; Access to directory of kanidm certs, since these are self-signed
  # Not required when system cert store has root certificate of publicly signed certificate.
  users.users.bert-proesmans.extraGroups = [ "nginx" ];

  services.kanidm = {
    enableServer = true;
    # DEBUG; Client disabled due to custom root certificate requirements.
    # This is a non-issue with publicly issued certificates.
    enableClient = false;
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

    # clientSettings = {
    #   # TODO
    # };

    provision = {
      enable = true;
      instanceUrl = "https://127.204.0.1:8443";
      # D&M0Ln6%z9JA2Z%yyvg4*Dd0hRhb6y!H
      idmAdminPasswordFile = config.sops.secrets.test-secret.path;
      # ERROR; Certificate is bound to DNS name won't validate IP address
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

      systems.oauth2."test&&" = {
        displayName = "test";
        basicSecretFile = pkgs.writeText "oauth-pass" oauth-test-pass;
        preferShortUsername = true;
        # PKCE is currently not supported by immich
        allowInsecureClientDisablePkce = true;
        # RS256 is used instead of ES256 so additionally we need legacy crypto
        enableLegacyCrypto = true;
        scopeMaps."household.alpha" = [ "openid" "email" "profile" ];
        # WARN; URLs must end with a forward slash if path element is empty!
        originLanding = "https://auth.alpha.proesmans.eu/";
        originUrl = [
          "https://auth.alpha.proesmans.eu/oauth2/callback"
        ];
      };

      systems.oauth2."photos" = {
        displayName = "Immich SSO";
        #basicSecretFile = config.sops.secrets.test-secret.path;
        basicSecretFile = pkgs.writeText "idm-admin-pw" imm-pass; # DEBUG
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
