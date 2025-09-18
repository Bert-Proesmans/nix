{ lib, config, ... }:
let
  buddy-tailscale-ip = lib.pipe config.proesmans.facts.buddy.services [
    # Want the service endpoint over tailscale
    (lib.filterAttrs (_ip: v: builtins.elem "tailscale" v.tags))
    (lib.mapAttrsToList (ip: _: ip))
    (lib.flip builtins.elemAt 0)
  ];

  # Hardcoded upstream
  statePath = "/var/lib/gatus";
in
{
  services.gatus.settings.announcements = [
    # {
    #   timestamp = "2025-08-15T12:00:00Z";
    #   # outage, warning, information, operational, none
    #   type = "information";
    #   message = "New monitoring dashboard features will be deployed next week";
    # }
  ];

  services.gatus.settings.maintenance = {
    start = "20:00";
    duration = "2h";
    timezone = "Europe/Brussels";
    every = [ ]; # Every day
  };

  networking.hosts = {
    "${buddy-tailscale-ip}" = [
      # No IP for alpha.idm is known on the internet
      "alpha.idm.proesmans.eu"

      # ERROR; wiki.proesmans.eu doesn't currently resolve over the internet
      # Temporarily connect to wiki application over tailscale tunnel
      "wiki.proesmans.eu"
      "alpha.wiki.proesmans.eu"
    ];
  };

  services.gatus = {
    enable = true;
    openFirewall = false;
    settings = {
      web.address = "[::1]";
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
          name = "Omega server 01";
          group = "core";
          url = "icmp://01-fart.omega.proesmans.eu";
          interval = "5m";
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
          url = "icmp://02-fart.omega.proesmans.eu";
          interval = "5m";
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
          interval = "5m";
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
            "[RESPONSE_TIME] < 150ms"
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
            "[RESPONSE_TIME] < 150ms"
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
            "[RESPONSE_TIME] < 150ms"
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
          url = "https://wiki.proesmans.eu/s/1f53ffce-0927-4a7c-a5bc-e14132cd81ff";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 150ms"
            "[BODY] == pat(*<h1 dir=\"ltr\">Proesmans.EU</h1>*)"
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
}
