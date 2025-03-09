{ lib, pkgs, config, utils, ... }:
{
  systemd.tmpfiles.settings."wip-backup-mount" = {
    "/backup".d = {
      user = "root";
      group = "root";
      mode = "0700";
    };

    "/backup"."a+".argument = "user:bert-proesmans:r-X,default:user:bert-proesmans:r-X";

    # NOTE; There are directory holes specifically left for security, they will be automatically created and owned
    # by root.

    "/backup/one-folder".d = {
      user = "bert-proesmans";
      group = "users";
      mode = "0700";
    };

    "/backup/two-folder".d = {
      user = "bert-proesmans";
      group = "users";
      mode = "0700";
    };

    "/backup/overlays/d_drive".d = {
      user = "bert-proesmans";
      group = "users";
      mode = "0700";
    };

    "/backup/overlays/d_drive/data".d = {
      user = "bert-proesmans";
      group = "users";
      mode = "0700";
    };
  };

  systemd.mounts = [
    ({
      description = "Backup bind mount /backup/one-folder";
      wantedBy = [ "multi-user.target" ];
      wants = [ "systemd-tmpfiles-setup.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];

      what = "/backup/one-folder";
      where = "/backup/overlays/d_drive/paths/one-folder";
      type = "none";
      options = "bind";
    })
    ({
      description = "Backup bind mount /backup/two-folder";
      wantedBy = [ "multi-user.target" ];
      wants = [ "systemd-tmpfiles-setup.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];

      what = "/backup/two-folder";
      where = "/backup/overlays/d_drive/paths/two-folder";
      type = "none";
      options = "bind";
    })
    ({
      description = "Overlay mount for backup drive_d";
      wantedBy = [ "multi-user.target" ];
      wants = [ "systemd-tmpfiles-setup.service" ];
      after = [
        "systemd-tmpfiles-setup.service"
        config.systemd.services."backup-d_drive-overlays-encrypted".name
      ];
      requires = [ config.systemd.services."backup-d_drive-overlays-encrypted".name ];

      what = "overlay";
      where = "/backup/d_drive/data";
      type = "overlay";
      options = lib.concatStringsSep "," [
        "lowerdir=/backup/overlays/d_drive/overlay/encrypted"
        "upperdir=/backup/overlays/d_drive/overlay/upper"
        "workdir=/backup/overlays/d_drive/overlay/work"
      ];
    })
  ];

  systemd.services."backup-d_drive-overlays-encrypted" =
    let
      requisiteMounts = [
        "${utils.escapeSystemdPath "/backup/overlays/d_drive/paths/one-folder"}.mount"
        "${utils.escapeSystemdPath "/backup/overlays/d_drive/paths/two-folder"}.mount"
      ];
    in
    {
      wantedBy = [ "multi-user.target" ];
      after = requisiteMounts;
      requires = requisiteMounts;

      path = [ pkgs.gocryptfs ];
      enableStrictShellChecks = true;
      script = ''
        ENCRYPT_CONFIG="/backup/overlays/d_drive/gocryptfs.conf"
        VAULT="/backup/overlays/d_drive/paths"
        ENCRYPT_MIDDLE="/backup/overlays/d_drive/overlay/encrypted"

        mkdir --parents "$ENCRYPT_MIDDLE"

        # TODO; Make sure config file is persisted!
        if [ ! -f "$ENCRYPT_CONFIG" ]; then
          gocryptfs -reverse -init -config "$ENCRYPT_CONFIG" -plaintextnames -passfile "$CREDENTIALS_DIRECTORY"/cryptfs "$VAULT"
        fi

        # Use -debug -fusedebug for debugging
        gocryptfs -reverse \
          -config "$ENCRYPT_CONFIG" -acl -rw -allow_other \
          -passfile "$CREDENTIALS_DIRECTORY"/cryptfs "$VAULT" "$ENCRYPT_MIDDLE"
      '';

      serviceConfig = {
        # After fork, continue start jobs. Important for dependency timing!
        Type = "forking";
        RemainAfterExit = false;
        LoadCredential = [ "cryptfs:/home/bert-proesmans/plain-secret.txt" ];
      };
    };

  # systemd.services.wip-backup = {
  #   enable = true;
  #   wantedBy = [ "default.target" ];
  #   wants = [ "systemd-tmpfiles-setup.service" ];
  #   after = [ "systemd-tmpfiles-setup.service" ];

  #   path = [
  #     pkgs.coreutils
  #     pkgs.mount
  #     pkgs.umount
  #     pkgs.gocryptfs
  #   ];
  #   enableStrictShellChecks = true;
  #   preStart = ''
  #     # Require setuid fusermount
  #     export PATH=${config.security.wrapperDir}:$PATH

  #     VAULT="/backup/paths"
  #     DRIVE="/backup/d_drive/data"

  #     ENCRYPT_CONFIG="/backup/d_drive/gocryptfs.conf"
  #     ENCRYPT_MIDDLE="/backup/d_drive/overlay/encrypted"
  #     OVERLAY_WORK="/backup/d_drive/overlay/work"
  #     OVERLAY_UPPER="/backup/d_drive/overlay/upper"

  #     mkdir --parents "$VAULT" "$DRIVE" "$ENCRYPT_MIDDLE" "$OVERLAY_WORK" "$OVERLAY_UPPER"

  #     cat /proc/"$BASHPID"/uid_map

  #     # TODO; Make sure config file is persisted!
  #     if [ ! -f "$ENCRYPT_CONFIG" ]; then
  #       gocryptfs -reverse -init -config "$ENCRYPT_CONFIG" -plaintextnames -passfile "$CREDENTIALS_DIRECTORY"/cryptfs "$VAULT"
  #     fi

  #     gocryptfs -debug -fusedebug -reverse -config "$ENCRYPT_CONFIG" -acl -rw -passfile "$CREDENTIALS_DIRECTORY"/cryptfs "$VAULT" "$ENCRYPT_MIDDLE"

  #     # TODO overlay mount
  #   '';

  #   script = ''
  #     ls -laa /backup/paths /backup/d_drive 
  #     ls -Rlaa /backup/d_drive/overlay/encrypted
  #   '';

  #   serviceConfig = {
  #     User = "bert-proesmans";
  #     LoadCredential = [ "cryptfs:/home/bert-proesmans/plain-secret.txt" ];

  #     RuntimeDirectory = [
  #       "test-backup/root-mount"
  #       "test-backup/root-mount/backup"
  #       "test-backup/root-mount/backup/paths"
  #     ];
  #     RootDirectory = "/run/test-backup/root-mount";
  #     StateDirectory = "test-backup";
  #     LogsDirectory = "test-backup";

  #     # Need private user namespace for unprivileged fuse-mounting
  #     PrivateUsers = true;
  #     PrivateMounts = true;
  #     BindReadOnlyPaths = [
  #       builtins.storeDir
  #       "/etc" # For FUSE
  #     ];
  #     BindPaths = [
  #       "/dev/fuse"

  #       "/var/log/test-backup:/backup/paths/logs" # DEBUG
  #       "/backup/one-folder:/backup/paths/one" # Backup directory
  #       "/backup/two-folder:/backup/paths/two" # Backup directory
  #       "/backup/overlays/d_drive:/backup/d_drive" # Persisted overlay
  #     ];
  #   };
  # };
}
