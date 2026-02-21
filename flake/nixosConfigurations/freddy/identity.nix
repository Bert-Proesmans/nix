{
  lib,
  pkgs,
  config,
  ...
}:
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
    package = pkgs.kanidm_1_9;

    server.enable = true;
    server.settings = {
      # WARN; Setting http_client_address_info requires settings format version 2+
      version = "2";
      bindaddress = "127.0.0.1:8443";
      # HostName; alpha.idm.proesmans.eu, beta.idm.proesmans.eu ...
      # NOTE; Regional hostnames can be used as web resources under the webauthn+cookies specification
      #
      # HELP; Domain must be the same for all regional instances of IDM.
      domain = "idm.proesmans.eu";
      # HELP; Origin should be equal to hostname, and equal or subdomain to "domain".
      # ERROR; The origin is reported in the OpenID discovery reply. Client applications perform an exact
      # match on the dommain. This means that the entire OpenID authentication transaction must happen
      # on ONE specific regional instance!
      # eg application -openid-> omega.idm.proesmans.eu -user redirect-> omega.idm.proesmans.eu -token exchange-> omega.idm.proesmans.eu -> application
      # The application won't validate tokens issues by alpha.idm.proesmans.eu!
      # So the origin remains on idm.proesmans.eu, and webauthn-rs is configured to allow operations from subdomain.
      # REF; https://github.com/kanidm/kanidm/blob/4cc9acaeb03c2ad15a7530328c71cc04f2454309/server/lib/src/idm/server.rs#L198-L203
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
          supplier_cert = "MIIB9jCCAZygAwIBAgIBATAKBggqhkjOPQQDAjBMMRswGQYDVQQKDBJLYW5pZG0gUmVwbGljYXRpb24xLTArBgNVBAMMJGE5Yzc5NThiLWRkNmEtNDI0YS05MTkzLWMzMmM1MGU1MmEyMzAeFw0yNTA5MTgwOTEyNTlaFw0yOTA5MTgwOTEyNTlaMEwxGzAZBgNVBAoMEkthbmlkbSBSZXBsaWNhdGlvbjEtMCsGA1UEAwwkYTljNzk1OGItZGQ2YS00MjRhLTkxOTMtYzMyYzUwZTUyYTIzMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEHF26qqDTEiNslJCum36ALaz-59UbrbpUxdTnxPzSEsQg59LXALvOyMq6ri_Cs8-SL4-MOFimiyWWsYXigxylMqNvMG0wDAYDVR0TAQH_BAIwADAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMB0GA1UdDgQWBBTaOaPuXmtLDTJVv--VYBiQr9gHCTAPBgNVHREECDAGhwRkdFQdMAoGCCqGSM49BAMCA0gAMEUCIQCLgHEOzUa6In7Arqdx5wbv2YR4aANsTo7FCQHiHYdvsAIgNPj8qPQe4cYhZTFqj1NHKvy6Wd7tDDZ5qrFJn4aZZB0=";
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

    client.enable = true;
    client.settings = {
      # ERROR; MUST MATCH _instance_ DNS hostname exactly due to certificate validation!
      uri = "https://omega.idm.proesmans.eu";
      verify_hostnames = true;
      verify_ca = true;
    };
  };
}
