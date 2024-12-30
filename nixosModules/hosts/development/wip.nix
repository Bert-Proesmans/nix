{ lib, pkgs, config, ... }:
let
  json-convert = pkgs.formats.json { };
in
{
  sops.secrets.test-secret = { };
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
}
