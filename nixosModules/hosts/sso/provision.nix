{ ... }: {
  services.kanidm.provision = {
    enable = true;
    autoRemove = true;
    # groups."alpha".members = [ "bert-proesmans" ];
    groups = {
      "idm_service_desk" = { }; # Builtin
      "alpha" = { };
    };
    persons."bert-proesmans" = {
      displayName = "Bert Proesmans";
      mailAddresses = [ "bert@proesmans.eu" ];
      groups = [
        # Allow credential reset on other persons
        "idm_service_desk" # tainted role
        "alpha"
      ];
    };
    # systems.oauth2."test" = { };
  };
}
