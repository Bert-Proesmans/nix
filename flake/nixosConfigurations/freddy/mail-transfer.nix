{
  lib,
  pkgs,
  config,
  ...
}:
{
  sops.secrets."sendmail-smtp" = { };
  sops.templates."nullmailer-remotes" = {
    owner = config.users.users.nullmailer.name;
    restartUnits = [ config.systemd.services.nullmailer.name ];
    # smtp.gmail.com smtp --port=465 --auth-login --user=gmail_address --pass=password --ssl
    content =
      let
        host = config.services.smtprelay.settings.hostname;
        port = toString config.proesmans.facts.self.service.mail.port;
        username = "freddy-host";
        password = config.sops.placeholder."sendmail-smtp";
      in
      ''
        ${host} smtp --port=${port} --ssl --auth-login --user=${username} --pass=${password}
      '';
  };

  services.nullmailer = {
    enable = true;
    setSendmail = true;
    remotesFile = config.sops.templates."nullmailer-remotes".path;
    config = {
      # NOTE; All destinations lead to adminaddr
      adminaddr = "systemadmin@proesmans.eu";
      # NOTE; Enveloppe From!
      allmailfrom = "freddy@omega.proesmans.eu";
      # ERROR; Must be an ACCEPTED MAIL-domain! The FQDN is not registered upstream as a mail-domain and will be blocked!
      me = "omega.proesmans.eu";
      # How long to wait on the upstream before send confirmation.
      # NOTE; This approach kills the connection and retries after pausetime.
      sendtimeout = 180; # 3 minutes
    };
  };

  # Allow local processes to call `sendmail`
  services.mail.sendmailSetuidWrapper.enable = true;
}
