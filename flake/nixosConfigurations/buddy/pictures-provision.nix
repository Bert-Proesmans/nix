{
  lib,
  pkgs,
  config,
  ...
}:
let
  # Exposed directories
  pictures-path = "/chroot/pictures";
  pictures-external-path = "/chroot/pictures-external";

  # Backend implementations.
  # NOTE; The ZFS mounts go straight into the host filesystem, with bind-mounts into the chroot at the right timing after
  # the chroot-tree is ready.
  #
  immichStatePath = "/var/lib/immich";
  # ERROR; Immich machine learning service is already using '/var/cache/immich'
  immichCachePath = "/var/cache/immich-server";
  immichExternalStatePath = "/var/lib/immich-external";
in
{
  # @@ IMMICH media location @@
  # Immich expects a specific directory structure inside its state directory (immichStatePath == config.services.immich.mediaLocation)
  # "library" => Originals are stored here => main dataset
  # "profile" => Original profile images are stored here => main dataset
  # "thumbs" => re-encoded material => cache dataset
  # "encoded-video" => re-encoded material => cache dataset
  # "upload" => not provisioned
  # "backups" => not provisioned
  #
  disko.devices.zpool.storage.datasets = {
    "media/immich/originals" = {
      type = "zfs_fs";
      # WARN; To be backed up !
      options.mountpoint = immichStatePath;
    };

    "media/immich/external" = {
      type = "zfs_fs";
      # WARN; To be backed up !
      options.mountpoint = immichExternalStatePath;
    };

    "media/immich/cache" = {
      type = "zfs_fs";
      # NOTE; Backup not necessary, can be regenerated
      options.mountpoint = immichCachePath;
    };
  };

  # Disable snapshots on the cache dataset
  services.sanoid.datasets."storage/media/immich/cache".autosnap = false;

  systemd.tmpfiles.settings."10-immich-state" = {
    "${immichStatePath}".z = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770"; # Sticky bit!
    };
    "${immichCachePath}".z = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770"; # Sticky bit!
    };
    "${immichExternalStatePath}".z = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770"; # Sticky bit!
    };
    #
    "${immichStatePath}/library".d = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770";
    };
    "${immichStatePath}/profile".d = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770";
    };
    "${immichCachePath}/thumbs".d = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770";
    };
    "${immichCachePath}/encoded-video".d = {
      user = config.users.users."immich".name;
      group = config.users.groups."pictures".name;
      mode = "1770";
    };
  };

  systemd.mounts = [
    {
      # Immich external
      wantedBy = [ "multi-user.target" ];
      requires = [ config.systemd.targets."chroot-tree".name ];
      after = [ config.systemd.targets."chroot-tree".name ];
      partOf = [ config.systemd.targets."chroot-tree".name ];
      what = immichExternalStatePath;
      where = pictures-external-path;
      type = "none";
      options = lib.concatStringsSep "," [
        # WARN; Do not allow Immich to make changes to external libraries
        "ro"
        "bind"
      ];
      unitConfig.RequiresMountsFor = [ immichStatePath ];
    }
    {
      # Immich state /
      wantedBy = [ "multi-user.target" ];
      requires = [ config.systemd.targets."chroot-tree".name ];
      after = [ config.systemd.targets."chroot-tree".name ];
      partOf = [ config.systemd.targets."chroot-tree".name ];
      what = immichStatePath;
      where = pictures-path;
      type = "none";
      options = lib.concatStringsSep "," [
        # NOTE; Recursive bind mount because other filesystems are mounted into this one;
        # - thumbs (cache)
        # - encoded-videos (cache)
        "rbind"
      ];
      unitConfig.RequiresMountsFor = [ immichStatePath ];
    }
    {
      # Immich /thumbs
      wantedBy = [ "multi-user.target" ];
      conflicts = [ "umount.target" ];
      requires = [ config.systemd.targets."chroot-tree".name ];
      after = [
        "systemd-tmpfiles-setup.service" # thumbs folder creation
        config.systemd.targets."chroot-tree".name
      ];
      partOf = [ config.systemd.targets."chroot-tree".name ];
      what = "${immichCachePath}/thumbs";
      where = "${immichStatePath}/thumbs"; # immichStatePath becomes recusive bind !
      type = "none";
      options = lib.concatStringsSep "," [
        "bind"
      ];
      unitConfig.RequiresMountsFor = [
        immichCachePath
        immichStatePath
      ];
      unitConfig.DefaultDependencies = false;
    }
    {
      # Immich /encoded-video
      wantedBy = [ "multi-user.target" ];
      conflicts = [ "umount.target" ];
      requires = [ config.systemd.targets."chroot-tree".name ];
      after = [
        "systemd-tmpfiles-setup.service" # encoded-video folder creation
        config.systemd.targets."chroot-tree".name
      ];
      partOf = [ config.systemd.targets."chroot-tree".name ];
      what = "${immichCachePath}/encoded-video";
      where = "${immichStatePath}/encoded-video"; # immichStatePath becomes recusive bind !
      type = "none";
      options = lib.concatStringsSep "," [
        "bind"
      ];
      unitConfig.RequiresMountsFor = [
        immichCachePath
        immichStatePath
      ];
      unitConfig.DefaultDependencies = false;
    }
  ];

  users.users."immich" = {
    group = config.users.groups."pictures".name;
    isSystemUser = true;
  };
  users.groups."pictures" = { };

  services.postgresql = {
    # ERROR; pg_dump: error: query failed: ERROR:  could not access file "$libdir/vchord": No such file or directory
    # NOTE; To be able to manipulate immich database backups, the vector libraries must be present!
    extensions = ps: [
      ps.pgvector
      ps.vectorchord
    ];
    settings.shared_preload_libraries = [ "vchord.so" ];
  };
}
