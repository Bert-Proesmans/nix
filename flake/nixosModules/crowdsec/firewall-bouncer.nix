{
  lib,
  utils,
  flake,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.crowdsec-firewall-bouncer;
in
{
  imports = [
    flake.inputs.crowdsec.nixosModules.crowdsec-firewall-bouncer
  ];

  options.services.crowdsec-firewall-bouncer = {
    # NOTE; Merges into (pkgs.formats.yaml {}).type
    # REF; https://github.com/NixOS/nixpkgs/blob/4b17a266c1d5988cbb33e49676317d593a3353e7/pkgs/pkgs-lib/formats.nix#L182-L198

    # ERROR; 'oneOf' does not seem to be mergeable..
    # settings = lib.mkOption {
    #   type = lib.types.nullOr (
    #     lib.types.oneOf [
    #       (lib.types.submodule {
    #         options = {
    #           _secret = lib.mkOption {
    #             type = lib.types.nullOr lib.types.str;
    #             description = ''
    #               The path to a file containing the value the option should be set to in the final
    #               configuration file.
    #             '';
    #           };
    #         };
    #       })
    #     ]
    #   );
    # };
  };

  config = lib.mkIf (cfg.enable) ({
    # Setup bouncer package from nixpkgs upstream by default
    services.crowdsec-firewall-bouncer.package = lib.mkDefault pkgs.crowdsec-firewall-bouncer;

    systemd.targets.crowdsec = {
      description = lib.mkDefault "Crowdsec";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "crowdsec-firewall-bouncer.service"
      ];
    };

    systemd.services.crowdsec-firewall-bouncer =
      let
        runtime-config-path = "/run/crowdsec-firewall-bouncer/config.yaml";
      in
      {
        serviceConfig = {
          RuntimeDirectory = [ "crowdsec-firewall-bouncer" ];
          RuntimeDirectoryMode = "0700";

          # NOTE; Force overwrite upstream calls to make use of customised settings file
          ExecStartPre = lib.mkForce [
            "${pkgs.writeShellScriptBin "create-bouncer-config" ''
              umask u=rwx,g=,o=

              # NOTE; Assumes YAML is a JSON superset!
              ${utils.genJqSecretsReplacementSnippet cfg.settings runtime-config-path}
            ''}/bin/create-bouncer-config"

            "${cfg.package}/bin/cs-firewall-bouncer -t -c ${runtime-config-path}"
          ];
          ExecStart = lib.mkForce "${cfg.package}/bin/cs-firewall-bouncer -c ${runtime-config-path}";
        };
      };
  });
}
