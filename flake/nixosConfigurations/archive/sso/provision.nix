{ ... }:
{
  services.kanidm.provision = {
    enable = true;
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
      scopeMaps."immich.access" = [
        "openid"
        "email"
        "profile"
      ];
      preferShortUsername = true;
      # PKCE is currently not supported by immich
      allowInsecureClientDisablePkce = true;
      # RS256 is used instead of ES256 so additionally we need legacy crypto
      enableLegacyCrypto = true;
    };
  };
}
