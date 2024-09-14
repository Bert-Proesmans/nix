{ lib
, system
, nixosLib
, flake
, withDevelopmentConfig ? false
}: (
  nixosLib.nixosSystem {
    lib = nixosLib;
    specialArgs = {
      special = {
        inherit (flake) inputs;
        inherit (flake.outputs.nixosModules) profiles;
      };
    };
    modules = [
      ({ special, config, modulesPath, ... }: {
        _file = ./bootstrap.nix;

        imports = [
          "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          special.profiles.remote-iso
        ]
        ++ lib.optionals withDevelopmentConfig [ special.profiles.development-bootstrap ];

        config = {
          _module.args.flake = flake;

          networking.hostName = lib.mkForce "installer";
          networking.domain = lib.mkForce "alpha.proesmans.eu";

          users.users.bert-proesmans = {
            isNormalUser = true;
            description = "Bert Proesmans";
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
            ];
          };

          isoImage.storeContents = lib.optionals withDevelopmentConfig [
            # NOTE; The development machine toplevel derivation is included as a balancing act;
            # Bigger ISO image size <-> 
            #     + Less downloading 
            #     + Less RAM usage (nix/store is kept in RAM on live boots!)
            flake.outputs.nixosConfigurations.development.config.system.build.toplevel
          ];

          nixpkgs.hostPlatform = lib.mkForce system;
          system.stateVersion = lib.mkForce config.system.nixos.version;
        };
      })
    ];
  }
).config.system.build.isoImage
