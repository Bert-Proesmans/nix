{ lib, flake, facts, home-configurations, config, ... }:
let
  cfg = config.proesmans.home-manager;
  cfg-users = config.users.users;
  types = lib.types;

  # Meta module used similarly to nixosModules to inject host facts and custom modules.
  wrapped-in-meta = _: original-module: { ... }: {
    _file = ./home-manager.nix;

    imports = [ original-module ];

    config = {
      _module.args.facts = facts;
    };
  };
  wrapped-home-configurations = builtins.mapAttrs wrapped-in-meta home-configurations;
in
{
  imports = [ flake.inputs.home-manager.nixosModules.default ];

  options.proesmans.home-manager = {
    enable = lib.mkEnableOption (lib.mdDoc "Enable user profile configuration for the users on the system");
    whitelist = lib.mkOption {
      # null is used to break infinite recursion.
      # The alternative would be to pre-populate the list with all users on the system.
      type = types.nullOr (types.listOf types.str);
      description = lib.mdDoc ''
        List of home-manager configuration attributes to install.
        The values in this array must overlap with the key-list of attribute-set `homeModules.users`.
      '';
      default = null;
      defaultText = lib.literalExpression "null";
      example = lib.literalExpression ''[ "root" ]'';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [ ]
        ++ (if cfg.whitelist != null then
        lib.flatten
          (lib.flip builtins.map cfg.whitelist (ref: [{
            assertion = builtins.hasAttr ref home-configurations;
            message = ''
              The whitelisted user reference ${ref} does not have a matching home-configuration.
              You can create a new home-configuration by defining flake output:
              homeModules.users.${ref} = {};
            '';
          }]))
        ++ (lib.flip builtins.map cfg.whitelist (ref: [{
          # WARN; Home-manager will create an empty users.users.<name> option without further details for
          # each user added through home-manager.users!
          # The assertion 'builtins.hasAttr ref cfg-users' will be true for all intersected user references!
          assertion =
            let
              user = cfg-users."${ref}";
              xor = a: b: a && !b || b && !a;
              isEffectivelySystemUser = user.isSystemUser || (user.uid != null && user.uid < 1000);
            in
            (builtins.hasAttr ref cfg-users) && (xor isEffectivelySystemUser user.isNormalUser);
          message = ''
            The whitelisted user reference '${ref}' does (probably) not have a matching user option in the system configuration.
            You can create a new user by defining the nixos options:
            users.users.${ref}.isNormalUser = true;
          '';
        }])) else [ ])
        ++ (if cfg.whitelist == null then
        lib.flatten
          (lib.flip lib.mapAttrsToList home-configurations (ref: _home-config: [{
            # WARN; Home-manager will create an empty users.users.<name> option without further details for
            # each user added through home-manager.users!
            # The assertion 'builtins.hasAttr ref cfg-users' will always be true like this.
            assertion =
              let
                user = cfg-users."${ref}";
                xor = a: b: a && !b || b && !a;
                isEffectivelySystemUser = user.isSystemUser || (user.uid != null && user.uid < 1000);
              in
              xor isEffectivelySystemUser user.isNormalUser;
            message = ''
              The home-configuration `homeModules.users.${ref}` is defined and included, but there is (probably) no matching system user defined in the configuration.
              You can create a new user by defining the nixos options:
              users.users.${ref}.isNormaluser = true;
            '';
          }])) else [ ]);

      # Enable more output when switching configuration
      home-manager.verbose = true;
      # Home-manager manages software assigned through option users.users.<name>.packages
      home-manager.useUserPackages = true;
      # Follow the system nix configuration instead of building/using a parallel index
      home-manager.useGlobalPkgs = true;
      home-manager.users =
        if cfg.whitelist == null then wrapped-home-configurations
        # Only keep the home configurations that intersect with the whitelist
        else builtins.intersectAttrs (builtins.listToAttrs (builtins.map (name: { inherit name; value = null; }) cfg.whitelist)) wrapped-home-configurations;
    })
  ];
}
