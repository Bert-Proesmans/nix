{ lib, pkgs, config, ... }: {
  config.systemd.services = lib.mkMerge (lib.flip lib.mapAttrsToList config.microvm.vms (
    name: microvm-config: {
      "microvm-suitcase-${name}" =
        let
          secrets = lib.mapAttrsToList (_: v: v) microvm-config.config.config.microvm.suitcase.secrets;
        in
        {
          enable = (builtins.length secrets) != 0;
          description = "Secrets for MicroVM '${name}'";
          after = [ "install-microvm-${name}.service" ];
          before = [ "microvm@${name}.service" ];
          partOf = [ "microvm@${name}.service" ];
          wantedBy = [ "microvms.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "secrets-microvm/${name}";
            RuntimeDirectoryMode = "751";
            PrivateTmp = true;
            ExecStart =
              let
                script = pkgs.writeShellApplication {
                  name = "create-secrets-volume-${name}";
                  runtimeInputs = [ pkgs.squashfsTools pkgs.coreutils ];
                  text = ''
                    d=
                    trap '[[ "$d" && -e "$d" ]] && rm --recursive "$d"' EXIT
                    d=$(mktemp --directory)
                    cd "$d"

                    ${lib.concatMapStringsSep "\n" (v: ''ln --symbolic "${v.source}" "${v.name}"'') secrets}

                    mksquashfs "$d" "$RUNTIME_DIRECTORY/suitcase.squashfs" -comp zstd -all-root -noappend -quiet
                    
                    chmod 0440 "$RUNTIME_DIRECTORY/suitcase.squashfs"
                    chown microvm:kvm "$RUNTIME_DIRECTORY/suitcase.squashfs"
                    ln --symbolic --force "$RUNTIME_DIRECTORY/suitcase.squashfs" "/var/lib/microvms/${name}/suitcase.squashfs"

                    rm --recursive "$d"
                  '';
                };
              in
              lib.getExe script;
            ExecStop =
              let
                script = pkgs.writeShellApplication {
                  name = "shred-secrets-volume-${name}";
                  runtimeInputs = [ pkgs.coreutils ];
                  text = ''
                    rm "/var/lib/microvms/${name}/suitcase.squashfs" || :

                    f="$RUNTIME_DIRECTORY/suitcase.squashfs"
                    [ -e "$f" ] && shred --remove=unlink "$f"
                  '';
                };
              in
              lib.getExe script;
          };
        };
    }
  ));
}
