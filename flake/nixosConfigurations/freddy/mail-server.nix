{
  lib,
  pkgs,
  config,
  ...
}:
{
  sops.secrets.mail-users = {
    format = "binary";
    sopsFile = ./mail-users.encrypted.yaml;
    owner = config.users.users.smtprelay.name;
  };

  security.acme.certs."freddy.omega.proesmans.eu" = {
    group = "smtprelay";
    reloadServices = [ config.systemd.services.smtprelay.name ];
  };

  # Redirect mailserver connection attempts to localhost
  networking.hosts."127.0.0.1" = [ config.services.smtprelay.settings.hostname ];

  # Relay setup;
  #
  # 1. Get certificate for host "freddy.omega.proesmans.eu"
  # 2. Configure certificate in smtprelay service below (remote_certificate, remote_key)
  # 3. Configure O365 server settings
  #   REF; https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365#configure-a-tls-certificate-based-connector-for-smtp-relay
  #   - Connector with TLS certificate on subject name "freddy.omega.proesmans.eu"
  #   - smtprelay remote: starttls://proesmans-eu.mail.protection.outlook.com:25
  #     WARN; Exchange online only supports EXPLICIT TLS (aka STARTTLS) and the relay client will choke on SMTPS
  # 4. Send test e-mail using swaks (nixpkgs#swaks)
  #    swaks --server localhost:<25> --from <anything>@proesmans.eu --to <anything>
  services.smtprelay =
    let
      certificate = "${config.security.acme.certs."freddy.omega.proesmans.eu".directory}/fullchain.pem";
      key = "${config.security.acme.certs."freddy.omega.proesmans.eu".directory}/key.pem";
    in
    assert config.proesmans.facts.self.service.mail.port == 465;
    {
      enable = true;

      tls.listener = { inherit certificate key; };
      tls.relay = { inherit certificate key; };

      settings = {
        log_level = "trace";
        hostname = "freddy.omega.proesmans.eu";
        listen = [
          "tls://127.0.0.1:465"
          "tls://[::1]:465"
          "tls://${config.proesmans.facts.self.host.tailscale.address}:465"
        ];
        allowed_nets = [
          "127.0.0.0/8"
          "::1/128"
          "${config.proesmans.facts.buddy.host.tailscale.address}/32"
        ];
        max_connections = 10;
        max_recipients = 5;
        allowed_sender = "^.*@(alpha\.|omega\.)?proesmans\.eu$";
        allowed_users = config.sops.secrets.mail-users.path;

        remotes = [
          "starttls://proesmans-eu.mail.protection.outlook.com:25"
        ];
      };
    };

  systemd.services.smtprelay = {
    requires = [ "acme-freddy.omega.proesmans.eu.service" ];
    wants = [
      # WARN; Binding to tailscale IP, so tailscale must be running and connected!
      "tailscaled-autoconnect.service"
    ];
    after = [
      "acme-freddy.omega.proesmans.eu.service"
      "tailscaled-autoconnect.service"
    ];
  };
}
