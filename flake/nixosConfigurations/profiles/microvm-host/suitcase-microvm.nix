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
          requiredBy = [ "microvm@${name}.service" ];
          partOf = [ "microvm@${name}.service" ];

          # Skip unit if the desired paths don't (yet) exist ?
          # unitConfig.ConditionPathExists = builtins.map (v: v.source) secrets;

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
            Group = "kvm";
            RuntimeDirectory = "secrets-microvm/${name}";
            RuntimeDirectoryMode = "750"; # SEEALSO; User/Group
            PrivateTmp = true;
            ExecStart =
              let
                script = pkgs.writeShellApplication {
                  name = "create-secrets-volume-${name}";
                  runtimeInputs = [ pkgs.coreutils pkgs.squashfs-tools-ng ];
                  text = ''
                    d=
                    trap '[[ "$d" && -e "$d" ]] && find "$d" -type f -exec shred --remove=unlink --zero {} +' EXIT
                    d=$(mktemp --directory)
                    cd "$d"

                    declare -A secrets=( # associative array
                      ${lib.concatMapStringsSep "\n  " (v: ''["${v.name}"]="${v.source}"'') secrets}
                    )
                    
                    # Copy each source recursively and dereference symlinks
                    for name in "''${!secrets[@]}"; do
                        source="''${secrets[$name]}"
                        dest="$d/$name"
                        
                        cp --dereference --recursive "$source" "$dest"
                    done
                    # Restrict permissions on files, cannot do that in gensquashfs command arguments
                    find "$d" -type f -exec chmod --quiet 400 {} +

                    squash="$RUNTIME_DIRECTORY/suitcase.squashfs"
                    gensquashfs --pack-dir "$d" --compressor zstd --all-root --defaults mode=0500 --force --quiet "$squash"

                    # NOTE; The plus-sign (+) at the end of the command groups as many files as possible
                    # in a single exec (for commands that support multiple file arguments)
                    find "$d" -type f -exec shred --remove=unlink --zero {} +
                    find "$d" -type d -exec rm --recursive --force {} +
                    
                    # ERROR; Qemu cannot open file, permission denied.
                    # Read+Write permissions required on image files! (even though the image is read-only)
                    chmod 0660 "$squash"
                    chown microvm:kvm "$squash"
                    ln --symbolic --force "$squash" "/var/lib/microvms/${name}/suitcase.squashfs"
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
                    [ -e "$f" ] && shred --remove=unlink --zero "$f"
                  '';
                };
              in
              lib.getExe script;
          };
        };
    }
  ));
}
