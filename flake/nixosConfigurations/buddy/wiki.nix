{
  lib,
  pkgs,
  config,
  ...
}:
let
  # Hardcoded upstream
  outlineStatePath = "/var/lib/outline";
in
{
  # WHyyyyyyyyyy does bookstack only support MySQL ??!!
  services.bookstack = {
    enable = false;
    hostname = "alpha.wiki.proesmans.eu";
    settings = { };
  };

  users.groups.mail = {
    # Members of this group have access to secret "password-smtp"
    members = [ config.services.outline.user ];
  };

  sops.secrets = {
    password-smtp.restartUnits = [ config.systemd.services.outline.name ];
    outline-oauth-secret = {
      mode = "0440";
      group = config.services.outline.group;
      restartUnits = [ config.systemd.services.outline.name ];
    };
  };

  disko.devices.zpool.storage.datasets."documents/wiki" = {
    type = "zfs_fs";
    # WARN; To be backed up !
    options.mountpoint = outlineStatePath;
    options.refquota = "10G";
  };

  # Second best option that is packages is outline, but no proper diagrams.net integration -_-
  #
  # There is also "docs" by the French government, but the project is too young and is currently a soulless copy.
  # It also requires an S3 backend Whyyyyyyyyyyyyyyyyyy?
  # SEEALSO; services.lasuite-docs
  #
  # The other wiki software is either mediawiki or desktop software that focuses on knowledge graphs.. I don't understand
  # why there is so little innovation on a basic markdown CMS with modern functionality (diagrams, multiplayer,
  # link/backlink tracking etc.
  # ... wiki.js v3 (if/when that ever releases)
  #
  #
  services.outline = {
    enable = true;
    port = 3561;
    databaseUrl = "local"; # automatically provision locally
    redisUrl = "local"; # automatically provision locally
    storage.storageType = "local";
    # logo = "<TODO>";
    # ERROR; alpha.wiki is not the correct public share url domain!
    # publicUrl = "https://alpha.wiki.proesmans.eu";
    # ERROR; using wiki.proesmans.eu breaks websockets!
    publicUrl = "https://wiki.proesmans.eu";
    # Instance is fronted with TLS proxy
    forceHttps = false;

    smtp = {
      host = "localhost";
      port = 587; # TODO; Fix STARTLS -> TLS ON
      secure = false; # TODO; Fix STARTLS -> TLS ON
      username = "alpha@proesmans.eu";
      passwordFile = config.sops.secrets.password-smtp.path;
      fromEmail = "wiki@proesmans.eu";
      replyEmail = "wiki@proesmans.eu";
    };

    ### REMEMBER TO DISABLE E-MAIL MAGIC LINK ON NEW INSTALLATIONS ###

    # NOTE; Open-ID autodiscovery works, but the nixos module hasn't been updated yet
    oidcAuthentication = null;
    # oidcAuthentication = {
    #   displayName = "Login met Proesmans account";
    #   OIDC_ISSUER_URL
    #   authUrl = "<TODO>";
    #   tokenUrl = "<TODO>";
    #   userinfoUrl = "<TODO>";
    #   clientId = "<TODO>";
    #   clientSecretFile = config.sops.secrets.outline-oauth-secret.path;
    #   usernameClaim = "preferred_username";
    #   scopes = [
    #     "openid"
    #     "profile"
    #     "email"
    #   ];
    # };
  };

  systemd.services.outline = lib.mkIf config.services.outline.enable {
    environment = {
      # Use current URL host to connect multiplayer editor
      COLLABORATION_URL = "auto";

      OIDC_DISPLAY_NAME = "Proesmans account";
      OIDC_ISSUER_URL = "https://alpha.idm.proesmans.eu/oauth2/openid/wiki";
      OIDC_CLIENT_ID = "wiki";
      # ERROR; Option does nothing.
      # There is no filtering of new accounts. Filtering is not necessary because there is no open/social provider connected.
      # ALLOWED_DOMAINS = "proesmans.eu";
      # Prevent automatic redirect into the SSO process (value doesn't matter)
      # NOTE; Only works if there are multiple login providers! If there is only OIDC the login page will always redirect.
      OIDC_DISABLE_REDIRECT = "yes";
    };

    script = lib.mkBefore ''
      export OIDC_CLIENT_SECRET="$(head -n1 ${lib.escapeShellArg config.sops.secrets.outline-oauth-secret.path})"
    '';

    unitConfig.RequiresMountsFor = [
      outlineStatePath
    ];
  };
}
