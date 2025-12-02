{ ... }:
let
  replication-origin = builtins.mapAttrs (
    _: fact: fact.service.kanidm-replication.uri fact.host.tailscale.address
  ) config.proesmans.facts;
in
{
  security.acme.certs."omega.idm.proesmans.eu" = {
    reloadServices = [ config.systemd.services.kanidm.name ];
    group = "kanidm";
  };

  # WARN; This service is setup as replicated node!
  services.kanidm = {
    enableServer = true;
    enableClient = true;
    package = pkgs.kanidm_1_7;

    # WARN; Setting http_client_address_info requires settings format version 2+
    serverSettings.version = "2";
    serverSettings = {
      bindaddress = "127.204.0.1:8443";
      # HostName; alpha.idm.proesmans.eu, beta.idm.proesmans.eu ...
      # ERROR; These hostnames cannot be used as web resources under the openid specification
      # NOTE; These hostnames can be used as web resources under the webauthn+cookies specification
      #
      # HELP; Domain and origin must be the same for all regional instances of IDM.
      domain = "idm.proesmans.eu";
      origin = "https://idm.proesmans.eu";
      # log_level = "debug";
      online_backup.enabled = false;
      # Accept proxy protocol from frontend stream handler
      http_client_address_info.proxy-v2 = [ "127.0.0.0/8" ];

      tls_chain = config.security.acme.certs."omega.idm.proesmans.eu".directory + "/fullchain.pem";
      tls_key = config.security.acme.certs."omega.idm.proesmans.eu".directory + "/key.pem";

      # Disallow writes on this system
      role = "ReadOnlyReplica";
      replication = {
        bindaddress =
          assert config.proesmans.facts.self.service.kanidm-replication.port == 8444;
          "0.0.0.0:8444";
        origin = replication-origin.self;

        # Partner(s)
        "${replication-origin.buddy}" = {
          # Pull changes from partner, don't push writes to partner
          type = "pull";
          # Partner certificate
          # WARNING; Expires every 180 days!
          #
          # Request certificate using command; kanidmd show-replication-certificate
          #
          # Renew certificate manually using command; kanidmd renew-replication-certificate
          #
          # NOTE; Hopefully the replication coordinator feature is finished soon!
          supplier_cert = "<TODO>";
          # How to resolve local database conflicts
          # true: partner changes win in conflict
          #
          # NOTE; This must always be true at the point of seeding a replication partner.
          # In an empty database there is no domain UUID set, which must be the same for all replication nodes.
          #
          # HELP; Keep at true for active-active high-availability with single master node as source of truth.
          automatic_refresh = true;
        };
      };

    };

    clientSettings = {
      # ERROR; MUST MATCH _instance_ DNS hostname exactly due to certificate validation!
      uri = "https://omega.idm.proesmans.eu";
      verify_hostnames = true;
      verify_ca = true;
    };
  };
}
