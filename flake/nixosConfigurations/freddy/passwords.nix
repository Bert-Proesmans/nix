{
  config,
  ...
}:
let
  # NOTE; Fixed upstream, with state-version <24.11
  vaultwardenStatePath = "/var/lib/bitwarden_rs";
in
{
  disko.devices.zpool.zroot.datasets."encryptionroot/sqlite/vaultwarden" = {
    type = "zfs_fs";
    # WARN; To be backed up !
    options.mountpoint = vaultwardenStatePath;
    options.refquota = "10G";
  };

  sops.secrets = {
    # Root ownership because used in template
    "vaultwarden-smtp" = { };
    "id-installation-bitwarden" = { };
    "key-installation-bitwarden" = { };
    "vaultwarden-oauth-secret" = { };
  };

  sops.templates."sensitive-vaultwarden.env" = {
    owner = "vaultwarden";
    restartUnits = [ config.systemd.services."vaultwarden".name ];
    content = ''
      SMTP_PASSWORD = ${config.sops.placeholder."vaultwarden-smtp"}
      PUSH_INSTALLATION_ID = ${config.sops.placeholder."id-installation-bitwarden"}
      PUSH_INSTALLATION_KEY = ${config.sops.placeholder."key-installation-bitwarden"}
      SSO_CLIENT_SECRET= ${config.sops.placeholder."vaultwarden-oauth-secret"}
    '';
  };

  # Keep mail traffic local
  networking.hosts."127.0.0.1" = [ "freddy.omega.proesmans.eu" ];

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    backupDir = null; # Not yet

    # WARN; Vaultwarden has no mechanism to load sensitive values from filepaths!
    # Sensitive values must be loaded into the service using a secure environment file.
    environmentFile = config.sops.templates."sensitive-vaultwarden.env".path;
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      IP_HEADER = "X-Forwarded-For";

      # ROCKET_LOG_LEVEL = "debug"; # DEBUG
      ROCKET_LOG_LEVEL = "critical";
      EXTENDED_LOGGING = true;
      # LOG_LEVEL = "debug"; # DEBUG
      LOG_LEVEL = "info";
      # Log timezone aware, for crowdsec
      LOG_TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S.%3f%z";

      # ADMIN_TOKEN = ""; # Empty to disable admin panel
      ADMIN_SESSION_LIFETIME = 5; # 5 minutes

      # WARN; Custom config, see overlays!
      # REF; https://github.com/dani-garcia/vaultwarden/discussions/6567
      WEBAUTH_DOMAIN = "passwords.proesmans.eu";
      DOMAIN = "https://omega.passwords.proesmans.eu"; # App URL

      SIGNUPS_ALLOWED = false; # SEEALSO; SIGNUPS_DOMAINS_WHITELIST
      WEBSOCKET_ENABLED = true;
      WEB_VAULT_ENABLED = true;
      SENDS_ALLOWED = true;
      # Control if users can assign individual other users for emergency access to their vault
      EMERGENCY_ACCESS_ALLOWED = true;
      EMAIL_CHANGE_ALLOWED = false;

      SIGNUPS_VERIFY = true;
      # Limit amount of signup e-mails to be sent to same e-mailaddress.
      # Expressed in seconds
      SIGNUPS_VERIFY_RESEND_TIME = 1800; # 30 minutes
      SIGNUPS_VERIFY_RESEND_LIMIT = 2;
      SIGNUPS_DOMAINS_WHITELIST = "proesmans.eu";

      # Who can create new organizations
      ORG_CREATION_USERS = "bert@proesmans.eu";
      INVITATIONS_ALLOWED = true;
      INVITATION_ORG_NAME = "Passwords | Proesmans.eu";
      INVITATION_EXPIRATION_HOURS = 168; # 7 days

      ORG_EVENTS_ENABLED = true;
      # Amount of time to retain event (audit) log.
      # Expressed in days
      EVENTS_DAYS_RETAIN = 365; # 1 year

      # Stop users from uploading many large blobs
      # WARN; Limits apply to _total_ storage, not per-item storage!
      # Limits are expressed in kilobytes
      ORG_ATTACHMENT_LIMIT = 1048576; # 1GB
      USER_ATTACHMENT_LIMIT = 20480; # 20MB
      USER_SEND_LIMIT = 1024; # 1MB

      TRASH_AUTO_DELETE_DAYS = ""; # Empty to not auto-delete thrashed items

      PASSWORD_ITERATIONS = "600000";
      PASSWORD_HINTS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;

      # Require an e-mail to be sent before login succeeds
      # This is useful to guarantee notifications went out and nothing goes under the radar
      REQUIRE_DEVICE_EMAIL = true;
      LOGIN_RATELIMIT_SECONDS = 60;
      LOGIN_RATELIMIT_MAX_BURST = 4;
      # Users cannot remember their device to skip further 2FA verifications
      DISABLE_2FA_REMEMBER = true;
      # Number of minutes to wait before 2FA-enabled login is considered incomplete.
      INCOMPLETE_2FA_TIME_LIMIT = 1; # 1 minute

      ## HIBP Api Key
      # HaveIBeenPwned API Key, request it here: https://haveibeenpwned.com/API/Key
      # WARN; No more one-time use API keys, it's a subscription service now. Use the https://haveibeenpwned.com/ website
      # directly instead.
      # HIBP_API_KEY=

      SMTP_HOST = "freddy.omega.proesmans.eu"; # Should be 127.0.0.1, see hosts above
      SMTP_PORT = 465;
      SMTP_FROM = "passwords@proesmans.eu"; # Passwords | Proesmans.eu <passwords@proesmans.eu>
      SMTP_SECURITY = "force_tls"; # force_tls | starttls | off
      SMTP_USERNAME = "vaultwarden";
      # SMTP_PASSWORD = # see environmentFile

      ## Enables push notifications (requires key and id from https://bitwarden.com/host)
      ## Details about mobile client push notification:
      ## - https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification
      PUSH_ENABLED = true;
      # PUSH_INSTALLATION_ID # see environmentFile
      # PUSH_INSTALLATION_KEY # see environmentFile
      # European Union Data Region Settings
      PUSH_RELAY_URI = "https://api.bitwarden.eu";
      PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";

      ## Single Sign-On (DOESN'T WORK, NOT IN STABLE YET)
      # REF; https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect
      ## This allows for self-service signup without invite.
      ## This _does not_ prevent users from entering their master password, the master password is the encryption key of their vault data!
      SSO_ENABLED = true;
      SSO_ONLY = false;
      ## On SSO Signup if a user with a matching email already exists make the association
      SSO_SIGNUPS_MATCH_EMAIL = true;
      ## Base URL of the OIDC server (auto-discovery is used)
      ##  - Should not include the `/.well-known/openid-configuration` part and no trailing `/`
      ##  - ${SSO_AUTHORITY}/.well-known/openid-configuration should return a json document: https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderConfigurationResponse
      SSO_AUTHORITY = "https://idm.proesmans.eu/oauth2/openid/passwords";
      ## Authorization request scopes. Optional SSO scopes, override if email and profile are not enough (`openid` is implicit).
      SSO_SCOPES = "email profile";
      ## Additional authorization url parameters (ex: to obtain a `refresh_token` with Google Auth).
      # SSO_AUTHORIZE_EXTRA_PARAMS="access_type=offline&prompt=consent"
      ## Activate PKCE for the Auth Code flow.
      SSO_PKCE = true;
      ## Set your Client ID and Client Key
      SSO_CLIENT_ID = "passwords";
      # SSO_CLIENT_SECRET = # see environmentFile

      # WARN; JSON string is quoted with a single quote (')!
      SSO_MASTER_PASSWORD_POLICY = "'${
        builtins.toJSON {
          enforceOnLogin = false; # `enforceOnLogin` is not supported at the moment
          minComplexity = 3; # (minComplexity=[0-4])
          minLength = 12;
          requireLower = false;
          requireNumbers = false;
          requireSpecial = false;
          requireUpper = false;
        }
      }'";
      ## Client cache for discovery endpoint. Duration in seconds (0 to disable).
      SSO_CLIENT_CACHE_EXPIRATION = 600; # 10m
    };
  };

  systemd.services.vaultwarden = {
    unitConfig.RequiresMountsFor = [
      vaultwardenStatePath
    ];
  };

  services.nginx.virtualHosts."omega.passwords.proesmans.eu" = {
    serverAliases = [ "passwords.proesmans.eu" ];
    useACMEHost = "omega.passwords.proesmans.eu";
    onlySSL = true;
    locations."/" = {
      proxyPass =
        assert config.services.vaultwarden.config.ROCKET_ADDRESS == "127.0.0.1";
        "http://127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
      proxyWebsockets = true;
    };
  };
}
