{
  lib,
  config,
  pkgs,
  ...
}:
{
  # Use these packages for manual bootstrapping of access+refresh tokens.
  #
  # 1. Start "emailproxy" as user "emailproxy" with a config that works
  #     sudo -u emailproxy <command>
  #     ERROR; The emailproxy user does not have permission to bind to priviledged ports!
  #     In your config copy, change those ports(<1024) to the non-privileged range (>1024)
  #     NOTE; Both the cache file path and passwords used must be the same as in the real/live situation!
  # 2. Run swaks from another terminal
  #     swaks --server localhost:<1587/587> --from <anything> --to <anything> --auth-user alpha@proesmans.eu --auth-password '<something consistent with applications password>'
  # 3. Do a manual sign-in with the authorization url provided by emailproxy (check the logs)
  # 4. Paste the authorization response back into the terminal so emailproxy can cache it
  #
  environment.systemPackages = [
    pkgs.proesmans.email-oauth2-proxy
    # Mail send tester
    # SEEALSO; email-oauth2-proxy.config:[alpha@proesmans.eu]
    pkgs.swaks
  ];

  users.users.emailproxy = {
    isSystemUser = true;
    group = "emailproxy";
  };
  users.groups.emailproxy = { };
  users.groups.mail = {
    # Members of this group have access to secret "password-smtp"
    members = [ "emailproxy" ];
  };

  security.acme.certs."alpha.mail.proesmans.eu" = {
    group = "emailproxy";
    reloadServices = [ config.systemd.services."email-oauth2-proxy".name ];
  };

  sops.secrets.graph-mail-secret.owner = "emailproxy";
  sops.secrets.password-smtp = {
    group = "mail";
    mode = "0440";
  };

  sops.templates."email-oauth2-proxy.config" = {
    owner = "emailproxy";
    restartUnits = [ config.systemd.services."email-oauth2-proxy".name ];
    # STARTLS config - TODO SSL the connections between client<->proxy!
    #
    # local_starttls = True
    # local_certificate_path = ${
    #   config.security.acme.certs."alpha.mail.proesmans.eu".directory
    # }/fullchain.pem
    # local_key_path = ${config.security.acme.certs."alpha.mail.proesmans.eu".directory}/key.pem
    content = ''
      [Email OAuth 2.0 Proxy configuration file]
        format = This file's format is documented at docs.python.org/library/configparser#supported-ini-file-structure. Values
          that span multiple lines should be indented deeper than the first line of their key (as in this comment). Quoting
          of values is not required. Documentation sections can be removed if needed (though it is advisable to leave these
          in place for reference) - thw only required sections are the individual server and account items of your setup.

      [emailproxy]
        documentation = The client SMTP password is not used for authentication, but for encryption/decryption of access_token!
          This means _pre-seeding and all applications_ must know the same "password" per sending account!
        delete_account_token_on_password_error = False

      [SMTP-587]
        documentation = The header means "listen on port 587 for protocol SMTP"! Connect your client to port 587.
          The properties within this section declare exchange online as the upstream relay. The FROM e-mail address must match one of
          the definition headers below, those credentials will be used for the specific e-mail.
          **ERROR**: While pre-seeding access_token manually, the service will not start because of this privileged port and exit 
          with permission denied error!
          TODO; Setup TLS, it doesn't look like STARTLS properly works(?)
        server_address = smtp.office365.com
        server_port = 587
        server_starttls = True
        local_address = 127.0.0.1

      [alpha@proesmans.eu]
        documentation = Decided against "resource owner password credentials grant (ROPCG)" flow at the expense of manually/interatively bootstrapping
          the first oauth access+refresh token!
          Create an application with delegated permissions 'SMTP.send' and 'offline_access' (these permissions pop up when searched verbatim under Graph API section).
          Mail.Send.Shared is for sending e-mail making use of a different sending account (shared mailbox) as the sender e-mail entity (other mailbox/distribution list).
          **NOTE**; Server-side configuration;
            - Application registration
            - Shared mailbox per server/privilege level (example; alpha@proesmans.eu)
            - Distribution lists per application (example; pictures@proesmans.eu)
            - Delegated permission "send as/send on behalf" for shared mailbox on distribution list (example; alpha@ + send as on top of pictures@)
          **ERROR**: Pre-seeding access_token requires a tty !!
        permission_url = https://login.microsoftonline.com/452f3fc6-5afd-400a-8d11-f14a7755d71d/oauth2/v2.0/authorize
        token_url = https://login.microsoftonline.com/452f3fc6-5afd-400a-8d11-f14a7755d71d/oauth2/v2.0/token
        oauth2_scope = https://outlook.office.com/SMTP.Send offline_access
        redirect_uri = https://localhost
        client_id = aea54598-8d19-477d-82d7-82b75e73bfad
        client_secret = ${config.sops.placeholder."graph-mail-secret"}
    '';
  };

  # NOTE; This lacks fine-grained access control on the multiplexer/proxy side!
  # A better solution is SMTP2Graph, the best solution is Postfix+SASL.
  #
  # For my simple deployment this is currently "good enough", the biggest issue currently is building up domain reputation.
  systemd.services."email-oauth2-proxy" = {
    description = "Email OAuth 2.0 Proxy";
    wantedBy = [ "multi-user.target" ];
    requires = [ "acme-alpha.mail.proesmans.eu.service" ];
    after = [ "acme-alpha.mail.proesmans.eu.service" ];
    serviceConfig = {
      ExecStart = builtins.concatStringsSep " " [
        (lib.getExe pkgs.proesmans.email-oauth2-proxy)
        # No interaction, write out everything to stdout
        "--no-gui"

        # Make user copy/paste authentication (contrary to automated --local-server-auth)
        "--external-auth"

        #
        "--config-file \"${config.sops.templates."email-oauth2-proxy.config".path}\""

        # ERROR; By default the credentials are stored inside the configuration file, but this file is very likely
        # read-only and publicly accessible!
        "--cache-store \"/var/lib/email-oauth2-proxy/credentials.cache\""

        # "--debug" # DEBUG
      ];
      Restart = "always";
      TimeoutSec = 20;
      RestartSec = 60;
      User = "emailproxy";
      Group = "emailproxy";
      StateDirectory = "email-oauth2-proxy";
      StateDirectoryMode = "0700";
      # NOTE; Capability required to bind to privileged network ports
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    };
    unitConfig =
      let
        inherit (config.systemd.services."email-oauth2-proxy".serviceConfig) TimeoutSec;
        maxTries = 5;
        bufferSec = 5;
      in
      {
        # The max. time needed to perform `maxTries` start attempts of systemd
        # plus a bit of buffer time (bufferSec) on top.
        StartLimitIntervalSec = TimeoutSec * maxTries + bufferSec;
        StartLimitBurst = maxTries;
      };
  };
}
