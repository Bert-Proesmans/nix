{
  lib,
  config,
  pkgs,
  ...
}:
{
  services.forgejo = {
    enable = true;
    # useWizard = false; # DEBUG
    database.type = "postgres";
    database.createDatabase = true;

    dump.enable = false;
    # REF; https://forgejo.org/docs/v11.0/admin/config-cheat-sheet/
    settings = {
      default = {
        # dev/prod
        RUN_MODE = "dev";
      };
      cache = {
        # REF; https://forgejo.org/docs/latest/admin/setup/recommendations/#cacheadapter
        ADAPTER = "twoqueue";
        HOST = ''{"size":100, "recent_ratio":0.25, "ghost_ratio":0.5}'';
      };
      quota.enabled = true;
      "quota.default".TOTAL = "2G";
      service = {
        # ERROR; Must keep open general registrations for OpenID self-registration
        DISABLE_REGISTRATION = false;
        # NOTE; Only allow
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        # NOTE; Toggle login form availability
        ENABLE_INTERNAL_SIGNIN = true;
        # WARN; Disable HTTP basic authentication
        ENABLE_BASIC_AUTHENTICATION = false;
        # NOTE; Send mails out for server activity
        ENABLE_NOTIFY_MAIL = true;
      };
      openid = {
        # euuuhh...
        # TODO
        ENABLE_OPENID_SIGNIN = false;
      };
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      # NOTE; Forgejo command-line application for instance administration
      # WARN; Type of 'config.services.forgejo.stateDir' is str, NOT VALIDATED!
      name = "forgejo";
      runtimeInputs = [ config.services.forgejo.package ];
      text = ''
        SUDO='exec'
        if [ "$USER" != "${config.services.forgejo.user}" ]; then
          ${
            if config.security.sudo.enable then
              "SUDO='exec ${config.security.wrapperDir}/sudo -u ${config.services.forgejo.user}'"
            else
              ">&2 echo 'Aborting, forgejo must be run as user `${config.services.forgejo.user}`!'; exit 2"
          }
        fi

        if [ $# -eq 0 ]; then
          # Prevent starting the forgejo web-server with the same database but broken, incomplete in comparison to systemd unit,
          # environment.
          >&2 echo "No arguments supplied, this forgejo command doesn't do anything by default"
          >&2 echo "Call forgejo --help for available actions"
          exit 0
        fi

        $SUDO forgejo --work-path '${lib.escapeShellArg config.services.forgejo.stateDir}' "$@"
      '';
    })
  ];
}
