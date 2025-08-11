{
  lib,
  pkgs,
  config,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [
    9000
    9200
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "resilio-sync"
    ];

  environment.systemPackages = [ pkgs.resilio-sync ];

  sops.secrets.resilio-license = {
    format = "binary";
    sopsFile = ./resilio-license.encrypted.json;
    restartUnits = [
      config.systemd.services.resilio.name
    ];
  };
  services.resilio = {
    # Use `rslsync --dump-sample-config´ to view an example configuration
    enable = true;
    checkForUpdates = false;
    licenseFile = config.sops.secrets.resilio-license.path;
    httpListenAddr = "0.0.0.0";
    httpListenPort = 9000;
    useUpnp = false;
    # ERROR; If shares are defined, the webUI must be disabled (according to the options doc)
    enableWebUI = false;
    storagePath = "/var/lib/resilio-sync";
    sharedFolders = [
      {
        directory = "/tmp/sync_test";
        knownHosts = [ ]; # TODO ?
        searchLAN = true;
        # Use `rslsync --generate-secret` to generate a read-write key for a shared folder
        secretFile = "/tmp/resilio-secret";
        useDHT = true;
        useRelayServer = true;
        useSyncTrash = true;
        useTracker = true;
      }
    ];
  };

  services.opencloud = {
    enable = false;
    address = "0.0.0.0";
    port = 9200;
    # ERROR; URL must resolve correctly from the client perspective _and also_ the current host!
    url = "https://169.254.245.139:9200";
    # NOTE; Environment variables override the configuration from settings.
    environment = {
      IDM_CREATE_DEMO_USERS = "false";
      # OC_LOG_LEVEL = "debug";
      # OC_LOG_LEVEL = "info";
      OC_LOG_LEVEL = "error";

      OC_INSECURE = "true"; # self-signed cert if combined with https url
      PROXY_INSECURE_BACKENDS = "true";
    };
    environmentFile = null;

    settings = {
      proxy = {
        auto_provision_accounts = true;
        oidc = {
          rewrite_well_known = false; # Only for external IDPs
        };
        # role_assignment = {
        #   driver = "oidc";
        #   oidc_role_mapper = {
        #     role_claim = "opencloud_roles";
        #   };
        # };
      };
      web = {
        web = {
          config = {
            oidc = {
              scope = "openid profile email opencloud_roles";
            };
          };
        };
      };

    };
  };
}
