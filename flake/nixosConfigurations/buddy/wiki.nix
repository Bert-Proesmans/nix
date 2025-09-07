{
  lib,
  pkgs,
  config,
  ...
}:
{
  # WHyyyyyyyyyy does bookstack only support MySQL ??!!
  services.bookstack = {
    enable = false;
    hostname = "alpha.wiki.proesmans.eu";
    settings = { };
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
  services.outline = {
    enable = false; # Not yet
    publicUrl = "https://alpha.wiki.proesmans.eu";
    port = 3561;
    databaseUrl = "local"; # automatically provision locally
    redisUrl = "local"; # automatically provision locally
    storage.type = "local";
    logo = "<TODO>";

    smtp = {
      host = "localhost";
      port = 587; # TODO; Fix STARTLS -> TLS ON
      secure = false; # TODO; Fix STARTLS -> TLS ON
      username = "alpha@proesmans.eu";
      passwordFile = "<TODO>";
      fromEmail = "<TODO>";
      replyEmail = "<TODO>";
    };

    oidcAuthentication = {
      displayName = "Login met Proesmans account";
      authUrl = "<TODO>";
      tokenUrl = "<TODO>";
      userinfoUrl = "<TODO>";
      clientId = "<TODO>";
      clientSecretFile = "<TODO>";
      usernameClaim = "preferred_username";
      scopes = [
        "openid"
        "profile"
        "email"
      ];
    };
  };
}
