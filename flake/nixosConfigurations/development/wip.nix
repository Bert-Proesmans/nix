{ lib, ... }:
let
  # Hardcoded upstream
  statePath = "/var/lib/gatus";
in
{
  services.gatus.settings.announcements = [
    {
      timestamp = "2025-08-15T12:00:00Z";
      # outage, warning, information, operational, none
      type = "information";
      message = "New monitoring dashboard features will be deployed next week";
    }
  ];

  services.gatus.settings.maintenance = {
    start = "20:00";
    duration = "4h";
    timezone = "Europe/Brussels";
    every = [ ]; # Every day
  };

  services.gatus = {
    enable = true;
    openFirewall = false;
    settings = {
      web.address = "[::1]";
      web.port = 8080;
      ui = {
        title = "Health | Proesmans.eu";
        description = "Status information of all family services";
        header = "Health Dashboard";
        # Enables light mode by default (overridden by user preference)
        dark-mode = false;
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
          url = "icmp://100.116.84.29"; # Tailscale forward
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
          name = "Identity management"; # Master node
          group = "services";
          url = "https://idm.proesmans.eu/ui/login";
          interval = "5m";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 150ms"
            "[BODY] == pat(*<h3>Kanidm idm.proesmans.eu</h3>*)"
            # ERROR; .eu toplevel domain registry doesn't publish expiration dates publicly
            # "[DOMAIN_EXPIRATION] > 720h"
            "[CERTIFICATE_EXPIRATION] > 10d"
          ];
          maintenance-windows = [ ];
        }
        {
          enabled = true;
          name = "Pictures";
          group = "services";
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
      ];
      # security.oidc = {
      #   issuer-url = "https://idm.proesmans.eu";
      #   client-id = "status";
      #   client-secret = "<TODO>";
      #   redirect-url = "https://omega.status.proesmans.eu/authorization-code/callback";
      #   scopes = [ "openid" ];
      # };
    };
  };
}
