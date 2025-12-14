{
  lib,
  pkgs,
  config,
  ...
}:
let
  bookstackUser = config.services.bookstack.user;

  # Hardcoded upstream behind services.mysql
  databaseSocket = "/run/mysqld/mysqld.sock";
in
{
  sops.secrets = {
    # NOTE; Secrets are loaded through the SystemD LoadCredential system, so they can remain owned by root!
    "bookstack-key-file" = {
      inherit (config.services.bookstack) group;
      mode = "0440";
      restartUnits = [ "phpfpm-bookstack.service" ];
    };
    "bookstack-oauth-secret" = {
      inherit (config.services.bookstack) group;
      mode = "0440";
      restartUnits = [ "phpfpm-bookstack.service" ];
    };
    # bookstack-mail-user-password.restartUnits = [];
  };

  services.mysql = {
    ensureDatabases = [ bookstackUser ];
    ensureUsers = [
      {
        name = bookstackUser;
        ensurePermissions = {
          "${bookstackUser}.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  services.bookstack = {
    enable = true;
    hostname = "omega.wiki.proesmans.eu";
    settings = {
      # Generate key using;
      # echo "base64:$(head -c 32 /dev/urandom | base64)"
      APP_KEY_FILE = config.sops.secrets.bookstack-key-file.path;
      #
      # DB_HOST = "";
      # DB_PORT = "";
      DB_SOCKET = databaseSocket;
      DB_DATABASE = bookstackUser;
      DB_USERNAME = bookstackUser;
      # DB_PASSWORD_FILE = "";
      #
      # MAIL_HOST = "";
      # MAIL_PORT = 465;
      # MAIL_PASSWORD_FILE = "";
      # MAIL_USER = "";
      # MAIL_ENCRYPTION = "tls";
      # MAIL_FROM = "";
      # MAIL_FROM_NAME = "";

      APP_VIEWS_BOOKS = "list"; # Hide book images from public books overview
      ALLOW_UNTRUSTED_SERVER_FETCHING = false; # Disables wkhtmltopdf
      REVISION_LIMIT = false; # Disable auto-removal of page revisions (100 by default)
      RECYCLE_BIN_LIFETIME = -1; # Disable auto-removal of recycle bin content
      APP_PROXIES = lib.concatStringsSep "," [
        "127.0.0.1"
      ];

      SESSION_SECURE_COOKIE = true; # only send cookies over https
      SESSION_LIFETIME = 10080; # minutes (7 days)

      # Link to our custom draw.io instance
      #
      # Custom draw.io parameters are used to define the interface and style of the content
      # REF; https://www.drawio.com/doc/faq/supported-url-parameters
      # DRAWIO = lib.concatStringsSep "&" [
      #   "https://draw.live.e-power.org/?embed=1&proto=json&spin=1" # Base url and require arguments
      #   "configure=1" # Sends configure javascript-event
      #   "lang=en"
      #   "stealth=1" # Disables features that require external web services
      #   "dark=auto"
      #   "ui=min" # Reduce the UI as much as possible
      #   "sketch=0" # Sketching contents
      #   "rough=0" # Sketching contents
      #   "grid=0" # Disable the background grid
      #   "layers=0" # Disable layer control
      #   # Plugins explore/tooltips/sql, very interesting stuff btw
      #   # REF; https://www.drawio.com/doc/faq/plugins
      #   "p=ex;tips;sql"
      # ];

      # ERROR; Cannot use the combination of password/oidc login, decided by the developers.
      #AUTH_METHOD = "standard"; # username/pass login only
      AUTH_METHOD = "oidc"; # oidc login only
      AUTH_AUTO_INITIATE = true; # auto-login
      OIDC_NAME = "Proesmans account";
      OIDC_CLIENT_ID = "bookstack";
      OIDC_CLIENT_SECRET_FILE = config.sops.secrets."bookstack-oauth-secret".path;
      OIDC_ISSUER = "https://idm.proesmans.eu/oauth2/openid/bookstack";
      OIDC_ISSUER_DISCOVER = true; # Use .well-known standard to find resource URLs
      # ERROR; Not working yet as of 25.05.2 because Graph API requires authentication for downloading profile picture
      OIDC_FETCH_AVATAR = true;
      # Additional scopes to send with the authentication request.
      # Many platforms require specific scopes to be requested for group data.
      # Multiple scopes can be added via comma separation.
      OIDC_ADDITIONAL_SCOPES = lib.concatStringsSep "," [ "groups" ];
      # Remove the user from roles that don't match OIDC groups upon login.
      # Note: While this is enabled the "Default Registration Role", editable within the
      # BookStack settings view, will be considered a matched role and assigned to the user.
      OIDC_REMOVE_FROM_GROUPS = false;
    };

    nginx = {
      onlySSL = true;
      useACMEHost = "omega.proesmans.eu";
    };
  };

  systemd.services.bookstack-setup = {
    after = [ "mysql.service" ];
  };

  services.nginx.virtualHosts = {
    "wiki.proesmans.eu" = {
      onlySSL = true;
      useACMEHost = "omega.proesmans.eu";
      globalRedirect = "omega.wiki.proesmans.eu";
    };
  };
}
