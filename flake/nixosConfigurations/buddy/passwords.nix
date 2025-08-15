{ ... }:
let
  # NOTE; Fixed upstream
  vaultwardenStatePath = "/var/lib/vaultwarden";
in
{
  disko.devices.zpool.storage.datasets."sqlite/vaultwarden" = {
    type = "zfs_fs";
    # WARN; To be backed up !
    options.mountpoint = vaultwardenStatePath;
  };

  services.vaultwarden = {
    enable = false; # Not yet
    dbBackend = "sqlite";
    backupDir = null; # Not yet

    environmentFile = null;
    config = {
      ROCKET_ADDRESS = "127.99.66.1";
      ROCKET_PORT = 8222;
      ROCKET_LOG = "critical";

      IP_HEADER = "X-Forwarded-For";
      # ADMIN_TOKEN_FILE = ""; # Empty to disable admin panel
      # ADMIN_TOKEN = "";
      ADMIN_SESSION_LIFETIME = 5; # 5 minutes
      EXTENDED_LOGGING = true;
      LOG_LEVEL = "info";

      DOMAIN = "https://alpha.passwords.proesmans.eu";
      SIGNUPS_ALLOWED = false;
      WEBSOCKET_ENABLED = true;
      WEB_VAULT_ENABLED = true;
      SENDS_ALLOWED = true;
      # Control if users can assign individual other users for emergency access to their vault
      EMERGENCY_ACCESS_ALLOWED = true;
      EMAIL_CHANGE_ALLOWED = false;

      # TODO; Setup SMTP and enable verification!
      SIGNUPS_VERIFY = false;
      # Limit amount of signup e-mails to be sent to same e-mailaddress.
      # Expressed in seconds
      SIGNUPS_VERIFY_RESEND_TIME = 1800; # 30 minutes
      SIGNUPS_VERIFY_RESEND_LIMIT = 2;
      SIGNUPS_DOMAINS_WHITELIST = "proesmans.eu";

      # Who can create new organizations
      ORG_CREATION_USERS = ""; # Empty to allow all users to create organizations
      INVITATIONS_ALLOWED = true;
      INVITATION_ORG_NAME = "Proesmans password manager";
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

      # TODO; Setup SMTP server
      # Require an e-mail to be sent before login succeeds
      # This is useful to guarantee notifications went out and nothing goes under the radar
      REQUIRE_DEVICE_EMAIL = false;
      LOGIN_RATELIMIT_SECONDS = 60;
      LOGIN_RATELIMIT_MAX_BURST = 4;
      # Users cannot remember their device to skip further 2FA verifications
      DISABLE_2FA_REMEMBER = true;
      # Number of minutes to wait before 2FA-enabled login is considered incomplete.
      INCOMPLETE_2FA_TIME_LIMIT = 1; # 1 minute

      # TODO; Register for HaveIBeenPwned
      ## HIBP Api Key
      ## HaveIBeenPwned API Key, request it here: https://haveibeenpwned.com/API/Key
      # HIBP_API_KEY=

      # TODO; Setup SMTP server
      # Use suffix _FILE to load secrets from files
      # HELO_NAME = "alpha.passwords.proesmans.eu";
      SMTP_HOST = "";
      SMTP_FROM = "";
      # SMTP_PORT = 465;
      # SMTP_SECURITY = "force_tls";
      # SMTP_AUTH_MECHANISM = "Login";
      # SMTP_USERNAME_FILE = config.sops.secrets.smtp-username.path;
      # SMTP_PASSWORD_FILE = config.sops.secrets.smtp-password.path;

      # TODO; Register for mobile push notifications
      ## Enables push notifications (requires key and id from https://bitwarden.com/host)
      ## Details about mobile client push notification:
      ## - https://github.com/dani-garcia/vaultwarden/wiki/Enabling-Mobile-Client-push-notification
      # PUSH_ENABLED=false
      # PUSH_INSTALLATION_ID=CHANGEME
      # PUSH_INSTALLATION_KEY=CHANGEME

      # WARNING: Do not modify the following settings unless you fully understand their implications!
      # Default Push Relay and Identity URIs
      # PUSH_RELAY_URI=https://push.bitwarden.com
      # PUSH_IDENTITY_URI=https://identity.bitwarden.com
      # European Union Data Region Settings
      # If you have selected "European Union" as your data region, use the following URIs instead.
      # PUSH_RELAY_URI=https://api.bitwarden.eu
      # PUSH_IDENTITY_URI=https://identity.bitwarden.eu

      # TODO; Setup SSO (requires release ?? to be available on nixpkgs)
      SSO_ENABLED = false;
      SSO_ONLY = false;
      # TODO; Setup SMTP server
      ## On SSO Signup if a user with a matching email already exists make the association
      # SSO_SIGNUPS_MATCH_EMAIL=true
      ## Allow unknown email verification status. Allowing this with `SSO_SIGNUPS_MATCH_EMAIL=true` open potential account takeover.
      # SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false
      ## Base URL of the OIDC server (auto-discovery is used)
      ##  - Should not include the `/.well-known/openid-configuration` part and no trailing `/`
      ##  - ${SSO_AUTHORITY}/.well-known/openid-configuration should return a json document: https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderConfigurationResponse
      SSO_AUTHORITY = "https://idm.proesmans.eu";
      ## Authorization request scopes. Optional SSO scopes, override if email and profile are not enough (`openid` is implicit).
      SSO_SCOPES = "email profile";
      ## Additional authorization url parameters (ex: to obtain a `refresh_token` with Google Auth).
      # SSO_AUTHORIZE_EXTRA_PARAMS="access_type=offline&prompt=consent"
      ## Activate PKCE for the Auth Code flow.
      SSO_PKCE = true;
      ## Set your Client ID and Client Key
      # SSO_CLIENT_ID=11111
      # SSO_CLIENT_SECRET=AAAAAAAAAAAAAAAAAAAAAAAA
      ## Optional Master password policy (minComplexity=[0-4]), `enforceOnLogin` is not supported at the moment.
      # SSO_MASTER_PASSWORD_POLICY='{"enforceOnLogin":false,"minComplexity":3,"minLength":12,"requireLower":false,"requireNumbers":false,"requireSpecial":false,"requireUpper":false}'
      ## Use sso only for authentication not the session lifecycle
      SSO_AUTH_ONLY_NOT_SESSION = true; # TODO; Experiment
      ## Client cache for discovery endpoint. Duration in seconds (0 to disable).
      SSO_CLIENT_CACHE_EXPIRATION = 86400; # 24h
    };
  };

  systemd.services.vaultwarden = {
    unitConfig.RequiresMountsFor = [
      vaultwardenStatePath
    ];
  };
}
