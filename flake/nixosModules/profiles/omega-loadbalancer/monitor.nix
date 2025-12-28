{ lib, config, ... }:
let
  fart-01-tailscale-ip = config.proesmans.facts."01-fart".host.tailscale.address;
  fart-02-tailscale-ip = config.proesmans.facts."02-fart".host.tailscale.address;
  freddy-tailscale-ip = config.proesmans.facts.freddy.host.tailscale.address;
  buddy-tailscale-ip = config.proesmans.facts.buddy.host.tailscale.address;

  # Hardcoded upstream
  statePath = "/var/lib/gatus";
in
{
  services.gatus.settings.announcements = [
    {
      timestamp = "2025-12-28T12:00:00Z";
      # outage, warning, information, operational, none
      type = "warning";
      # Markdown aware
      message = ''
        The [Pictures service](https://pictures.proesmans.eu) is being reworked to have higher availability.
        Outages will occur while this process is ongoing.

        Service migration is expected to finish by january 4th, 2026.
      '';
    }
  ];

  services.gatus.settings.maintenance = {
    start = "20:00";
    duration = "2h";
    timezone = "Europe/Brussels";
    every = [ ]; # Every day
  };

  networking.hosts = {
    "127.0.0.1" = [
      # ALPHA server expects a PROXY protocol header from load balancer
      "alpha.idm.proesmans.eu"
    ];
  };

  services.gatus = {
    enable = true;
    openFirewall = false;
    settings = {
      web.address = "127.0.0.1";
      web.port = 32854;
      ui = {
        title = "Health | Proesmans.eu";
        description = "Status information of all family services";
        header = "Health Dashboard";
        # Enables light mode by default (overridden by user preference)
        dark-mode = false;
        default-sort-by = "name";
        buttons = [
          {
            name = "Visit idm";
            link = "https://idm.proesmans.eu";
          }
        ];
      };
      storage = {
        type = "sqlite";
        path = lib.strings.normalizePath "${statePath}/data.db";
      };
      connectivity.checker.target = "1.1.1.1:53";
      connectivity.checker.interval = "1m";
      endpoints = [
        {
          enabled = true;
          name = "Freddy";
          group = "core";
          url = "icmp://${freddy-tailscale-ip}";
          interval = "30s";
          conditions = [
            "[CONNECTED] == true"
            "[RESPONSE_TIME] < 80ms"
          ];
          maintenance-windows = [ ];
          ui.hide-hostname = true;
        }
        {
          enabled = true;
          name = "Omega server 01";
          group = "core";
          url = "icmp://${fart-01-tailscale-ip}";
          interval = "30s";
          conditions = [
            "[CONNECTED] == true"
            "[RESPONSE_TIME] < 80ms"
          ];
          maintenance-windows = [ ];
          ui.hide-hostname = true;
        }
        {
          enabled = true;
          name = "Omega server 02";
          group = "core";
          url = "icmp://${fart-02-tailscale-ip}";
          interval = "30s";
          conditions = [
            "[CONNECTED] == true"
            "[RESPONSE_TIME] < 80ms"
          ];
          maintenance-windows = [ ];
          ui.hide-hostname = true;
        }
        {
          enabled = true;
          name = "Alpha server";
          group = "core";
          url = "icmp://${buddy-tailscale-ip}"; # Tailscale forward
          interval = "30s";
          conditions = [
            "[CONNECTED] == true"
            "[RESPONSE_TIME] < 80ms"
          ];
          maintenance-windows = [ ];
          ui.hide-hostname = true;
        }
        {
          enabled = true;
          name = "Mail server";
          group = "core";
          url = "starttls://smtp-mail.outlook.com:587";
          interval = "30m";
          client.timeout = "5s";
          conditions = [
            "[CONNECTED] == true"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
          ui.hide-hostname = true;
        }
        {
          enabled = true;
          name = "Identity management @alpha"; # Master node
          # group = "services";
          url = "https://alpha.idm.proesmans.eu/status";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 250ms"
            "[BODY] == true"
            # ERROR; .eu toplevel domain registry doesn't publish expiration dates publicly
            # "[DOMAIN_EXPIRATION] > 720h"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
        }
        {
          enabled = true;
          name = "Identity management";
          # group = "services";
          # NOTE; This could fallback from OMEGA to ALPHA!
          url = "https://idm.proesmans.eu/status";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 250ms"
            "[BODY] == true"
            # ERROR; .eu toplevel domain registry doesn't publish expiration dates publicly
            # "[DOMAIN_EXPIRATION] > 720h"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
        }
        {
          enabled = true;
          name = "Pictures";
          # group = "services";
          url = "https://pictures.proesmans.eu/api/server/ping";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 250ms"
            "[BODY].res == pong"
            # ERROR; .eu toplevel domain registry doesn't publish expiration dates publicly
            # "[DOMAIN_EXPIRATION] > 720h"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
        }
        {
          enabled = true;
          name = "Wiki";
          # group = "alpha";
          url = "https://wiki.proesmans.eu/";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 250ms"
            "[BODY] == pat(*<title>Wiki | Proesmans.EU</title>*)"
            # ERROR; .eu toplevel domain registry doesn't publish expiration dates publicly
            # "[DOMAIN_EXPIRATION] > 720h"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
        }
        {
          enabled = true;
          name = "Passwords";
          # group = "alpha";
          url = "https://passwords.proesmans.eu/alive";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 250ms"
            "len([BODY]) > 0"
            # ERROR; .eu toplevel domain registry doesn't publish expiration dates publicly
            # "[DOMAIN_EXPIRATION] > 720h"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
        }
      ];
      security.oidc = {
        issuer-url = "https://idm.proesmans.eu/oauth2/openid/status";
        client-id = "status";
        # NOTE; References environment key from sops template to inject
        # config.sops.secrets.gatus-oauth-secret.path
        client-secret = "\${OAUTH_SECRET}";
        redirect-url = "https://status.proesmans.eu/authorization-code/callback";
        scopes = [ "openid" ];
      };
    };
    environmentFile = config.sops.templates."gatus.env".path;
  };

  sops.secrets."gatus-oauth-secret" = { };
  sops.templates."gatus.env" = {
    restartUnits = [ config.systemd.services.gatus.name ];
    content = ''
      OAUTH_SECRET=${config.sops.placeholder."gatus-oauth-secret"}
    '';
  };

  services.nginx.virtualHosts."omega.status.proesmans.eu" = {
    useACMEHost = "omega-services.proesmans.eu";
    onlySSL = true;
    serverAliases = [ "status.proesmans.eu" ];
    locations."/" = {
      proxyPass =
        assert config.services.gatus.settings.web.address == "127.0.0.1";
        "http://127.0.0.1:${toString config.services.gatus.settings.web.port}";
    };
  };
}
