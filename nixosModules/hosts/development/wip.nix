{ lib, flake, special, meta-module, pkgs, config, ... }:
{
  systemd.tmpfiles.settings."wip-backup-mount" = {
    "/backup".d = {
      user = "root";
      group = "root";
      mode = "0700";
    };

    "/backup"."a+".argument = "user:bert-proesmans:r-X,default:user:bert-proesmans:r-X";

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
  };

  systemd.services.wip-backup = {
    enable = true;
    wantedBy = [ "default.target" ];
    wants = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];

    path = [ pkgs.coreutils pkgs.mount pkgs.umount pkgs.gocryptfs ];
    enableStrictShellChecks = true;
    preStart = ''
      VAULT="/backup/paths"
      DRIVE="/backup/d_drive/data"

      ENCRYPT_MIDDLE="/backup/d_drive/overlay/encrypted"
      OVERLAY_WORK="/backup/d_drive/overlay/work"
      OVERLAY_UPPER="/backup/d_drive/overlay/upper"

      mkdir --parents "$VAULT" "$DRIVE" "$ENCRYPT_MIDDLE" "$OVERLAY_WORK" "$OVERLAY_UPPER"

      # TODO; Make sure config file is persisted!
      if [ ! -f "$VAULT"/.gocryptfs.reverse.conf ]; then
        gocryptfs -reverse -init -plaintextnames -passfile "$CREDENTIALS_DIRECTORY"/cryptfs "$VAULT"
      fi

      gocryptfs -reverse -acl -rw -passfile "$CREDENTIALS_DIRECTORY"/cryptfs "$VAULT" "$ENCRYPT_MIDDLE"

      # TODO overlay mount
    '';

    script = ''
      ls -laa /backup/paths /backup/d_drive 
      ls -Rlaa /backup/d_drive/overlay/encrypted
    '';

    serviceConfig = {
      User = "bert-proesmans";
      LoadCredential = [ "cryptfs:/home/bert-proesmans/plain-secret.txt" ];

      RuntimeDirectory = [
        "test-backup/root-mount"
        "test-backup/root-mount/backup"
        "test-backup/root-mount/backup/paths"
      ];
      RootDirectory = "/run/test-backup/root-mount";
      StateDirectory = "test-backup";
      LogsDirectory = "test-backup";

      PrivateMounts = true;
      BindReadOnlyPaths = [
        builtins.storeDir
        "/etc" # For FUSE
      ];
      BindPaths = [
        "/dev/fuse"

        "/var/log/test-backup:/backup/paths/logs" # DEBUG
        "/backup/one-folder:/backup/paths/one" # Backup directory
        "/backup/two-folder:/backup/paths/two" # Backup directory
        "/backup/overlays/d_drive:/backup/d_drive" # Persisted overlay
      ];
    };
  };
}
