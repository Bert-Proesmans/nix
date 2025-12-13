{ ... }:
{
  services.smtprelay = {
    enable = true;
    settings = {
      log_level = "trace";
      hostname = "development.alpha.proesmans.eu";
      listen = [
        "127.0.0.1:25"
        "[::1]:25"
      ];
      max_connections = 10;
      max_recipients = 5;
      allowed_sender = "^(.*)@proesmans.eu$";

      # REF; https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365#configure-a-tls-certificate-based-connector-for-smtp-relay
      remotes = [
        "smtps://proesmans-eu.mail.protection.outlook.com:25"
      ];
    };
  };
}
