{
  lib,
  system,
  nixosLib,
  flake,
}:
let
  machine = flake.outputs.nixosConfigurations.test-zfs_encrypted_swap;
in
(nixosLib.nixosSystem {
  lib = nixosLib;
  specialArgs = {
    # Define arguments here that must be be resolvable at module import stage.
    #
    # For everything else use the _module.args option instead (inside configuration).
    flake = {
      inherit (flake) inputs;
      outputs = {
        # NOTE; Packages are not made available because they need to be re-evaluated within the package scope of the target host
        # anyway. Their evaluation could change depending on introduced overlays!
        inherit (flake.outputs) overlays homeModules;
      };
    };
  };
  modules = [
    (
      {
        config,
        modulesPath,
        pkgs,
        ...
      }:
      {
        _file = ./bootstrap.nix;

        imports = [
          "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
        ];

        config = {
          networking.hostName = lib.mkForce "installer";
          networking.domain = lib.mkForce "internal.proesmans.eu";

          boot.initrd.systemd.emergencyAccess = true;
          # enable zswap to help with low memory systems
          boot.kernelParams = [
            "zswap.enabled=1"
            "zswap.max_pool_percent=50"
            "zswap.compressor=zstd"
            # recommended for systems with little memory
            "zswap.zpool=zsmalloc"
          ];

          # Force be-latin keymap (= BE-AZERTY-ISO)
          console.keyMap = lib.mkDefault "be-latin1";
          time.timeZone = lib.mkDefault "Etc/UTC";

          # Ensure sshd starts at boot
          systemd.services.sshd.wantedBy = [ "multi-user.target" ];
          services.openssh.settings.PermitRootLogin = "prohibit-password";
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
          ];

          isoImage.storeContents = [ ];

          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
          ];
          nix.settings.connect-timeout = lib.mkForce 5;
          nix.settings.log-lines = lib.mkForce 25;

          nixpkgs.hostPlatform = lib.mkForce system;
          system.stateVersion = lib.mkForce config.system.nixos.release;

          # Make the image as small as possible #

          # Faster and (almost) equally as good compression
          isoImage.squashfsCompression = lib.mkForce "zstd -Xcompression-level 15";
          networking.wireless.enable = lib.mkForce false;
          documentation.enable = lib.mkForce false;
          documentation.nixos.enable = lib.mkForce false;
          documentation.man.man-db.enable = lib.mkForce false;

          # Drop ~400MB firmware blobs from nix/store, but this will make the host not boot on bare-metal!
          hardware.enableRedistributableFirmware = lib.mkForce false;

          # ERROR; The mkForce is required to _reset_ the lists to empty! While the default
          # behaviour is to make a union of all list components!
          # No GCC toolchain
          system.extraDependencies = lib.mkForce [ ];
          # Remove default packages not required for a bootable system
          environment.defaultPackages = lib.mkForce [ ];
          # prevents shipping nixpkgs, unnecessary if system is evaluated externally
          nix.registry = lib.mkForce { };

          environment.ldso32 = null;

          environment.systemPackages =
            let
              deployment-script = pkgs.writeShellApplication {
                name = "host-install-step";
                runtimeInputs = [
                  pkgs.openssh
                  pkgs.nixos-install
                ];
                # ERROR; The host-deploy task must know how to deploy the hostconfiguration
                # by name "development" !
                text = ''
                  if ! ssh-add -L >/dev/null 2>&1
                  then
                    echo "-- WARNING --"
                    echo "No SSH keys were found, so you'll have to use password login. Make sure to set a root password with \`sudo passwd\`"
                  fi

                  echo "Formatting disk"
                  # ERROR; lib.getExe doesn't work!
                  # ERROR; lib.getExe' doesn't work!
                  # NOTE; Disko uses trivial-scriptWriter with a non-path name for the derivation. This wraps the script into another derivation that
                  # links the script file at $out. (nixos-anywhere handles diskoscript the same)
                  # REF; https://github.com/nix-community/nixos-anywhere/blob/af70cbe8774492d03a0fb815f9d31bee83d856ce/src/nixos-anywhere.sh#L852
                  "${machine.config.system.build.diskoScript}"

                  echo "Installing system"
                  nixos-install --no-root-passwd --no-channel-copy --system "${machine.config.system.build.toplevel}"
                '';
              };
            in
            [
              (pkgs.writeShellApplication {
                name = "install-system";
                runtimeInputs = [ deployment-script ];
                text = ''
                  log_file="$(mktemp -t install-system.XXXXXX.log)"

                  trap 'echo "The full log journal can be found at path: $log_file"' EXIT

                  # Execute the wrapped script, capturing both stdout and stderr
                  "${lib.getExe deployment-script}" 2>&1 | tee "$log_file"

                  echo "Execution log is saved at: $log_file"
                '';
              })
            ];
        };
      }
    )
  ];
}).config.system.build.isoImage
