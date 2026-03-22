{
  lib,
  utils,
  pkgs,
  config,
  ...
}:
let
  fqdn-buddy = "buddy.internal.proesmans.eu";
in
{
  systemd.tmpfiles.settings."10-remote_fs" = {
    "/var/cache/rclone".d = {
      user = "root";
      group = "root";
      mode = "0700"; # u+rwx
    };

    "/mnt/remote".d = {
      # ERROR; Must restrict this directory because otherwise every user is allowed to read contents of the buddy host!
      # HINT; Use setfacl to allowlist users that need access through this path, for example fuse users (the kernel validates the entire path chain!)
      user = "root";
      group = "root";
      mode = "0000";
    };
    # NOTE; Open up mask to selectively allow through users
    "/mnt/remote"."a+".argument = "mask::r-x";
    "/mnt/remote/buddy-sftp".d = { };
    # NOTE; Premount directory creation necessary for mergerfs tags to improve merger intelligence
    "/mnt/remote/buddy-sftp/chroot/pictures".d = { };
    "/mnt/remote/buddy-sftp/chroot/pictures-external".d = { };
  };

  # ERROR; Must fix user-id of 'immich' because rclone only accepts numeric values as argument!
  # NOTE; Rclone remaps user-ids of mounted files to the one from immich, this is an overlay that impacts path permissions on
  # this host only (no impact on permissions on buddy, the source host).
  # users.users.immich.uid = 401;
  # users.groups.immich.gid = 401;
  #
  # ERROR; 'immich' user already exists on Freddy, so its runtime value is converted into declarative configuration.
  # Normally I'd set an ID between 400>X<1000.
  users.users.immich.uid = 987;
  users.groups.immich.gid = 983;

  systemd.services."rclone-ftp@buddy" = {
    description = "rclone: FTP mount for buddy";
    documentation = [ "man:rclone(1)" ];
    wants = [ "network-online.target" ];
    # Need these units but won't queue a startjob if they aren't active
    requisite = [ config.systemd.targets."buddy-online".name ];
    # WARN; The mount _does_ autostop if connection with buddy dissapears and shutdown can happen cleanly!
    wantedBy = [ config.systemd.targets."buddy-online".name ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
      config.systemd.targets."buddy-online".name
    ];

    path = [
      pkgs.util-linux # mountpoint
      pkgs.attr # sefattr
    ];
    enableStrictShellChecks = true;
    preStart =
      let
        configFile = pkgs.writeText "rclone.config" ''
          [buddy]
            type = sftp
            host = ${fqdn-buddy}
            user = freddy
            key_file = ${config.sops.secrets."buddy_ssh".path}
            known_hosts_file = /etc/ssh/ssh_known_hosts
            # WARN; Under other distros Rclone will dynamically detect the following settings and update the configuration file.
            # These settings have to be pre-provided because config-file changes are not possible/intended.
            shell_type = unix
            md5sum_command = md5sum
            sha1_command = sha1sum
        '';
      in
      ''
        # Copy static config file into writeable directory because Rclone keeps complaining about immutable configuration files..
        cp ${configFile} "$RUNTIME_DIRECTORY"/rclone.config

        mountpoint="/mnt/remote/buddy-sftp"
        # Code must run _before_ anything is mounted
        mountpoint --quiet "$mountpoint" && exit 1

        location="/mnt/remote/buddy-sftp/chroot/pictures"
        setfattr -n user.mergerfs.branch_mounts_here "$location"
      '';
    # ERROR; SFTP protocol does not support file attributes, marker cannot be set!
    # postStart = ''
    #   # The directory is marked for mergerfs to differentiate mounted/to be mounted.
    #   location="/mnt/remote/buddy-sftp/chroot/pictures"
    #   setfattr --name user.mergerfs.branch "$location"
    # '';

    serviceConfig = {
      Type = "notify";

      # ERROR; A 'single computer'-mount over sftp has a flaw that owner:group is fabricated on demand, there exist no _real_ inodes
      # to store custom permissions from the view of freddy!
      # SFTP has no linux permission model, there is single-user and modification bits.
      #
      # NOTE; The mount is forced to be owned by the immich user (freddy view), but actual permissions are validated on buddy.
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe' pkgs.rclone "rclone")
        "mount"
        ## -- SOURCE --
        "buddy:/"
        ## -- TARGET --
        "/mnt/remote/buddy-sftp"

        ## -- OPTIONS --
        # NOTE; Daemon mode doesn't produce any interesting logs!
        # HINT; Use logfile argument to store operational logging data
        # "vv" # DEBUG
        #
        # NOTE; Systemd does environment variable expansion too (enclosed with curly braces)!
        "--config=\${RUNTIME_DIRECTORY}/rclone.config"
        "--log-systemd"
        "--log-level=INFO"
        "--contimeout=60s" # SFTP session (/socket) timeout
        "--timeout=15s" # I/O timeout (however, filesystem I/O requests hang indefinite anyway)
        # REF; https://github.com/rclone/rclone/blob/master/vfs/vfs.md
        "--daemon-wait=15s" # Startup time
        # NOTE; Pre-created director using systemd-tmpfiles.
        # ERROR; Do not reuse the cache directory between rclone processes handling the same remotes, this clobbers the cache!
        "--cache-dir=/var/cache/rclone"
        # Read from source directly, write to VFS intermediate cache.
        # NOTE; Files written to cache, but not uploaded due to rclone termination or crash, will be written to source on next mount.
        # WARN; This is not a cache for attributes! The configuration options for the attribute cache are prefixed with 'attr-'
        "--vfs-cache-mode=writes"
        # Do not use "slow" (depends on backend type) file comparison operations
        "--vfs-fast-fingerprint"
        # Target size limit for the file cache.
        # NOTE; Files with open handle are not evicted from cache.
        # NOTE; Cache objects expire (see vfs-cache-max-age)!
        "--vfs-cache-max-size=10G"
        # NOTE; Since most useful operations are handled by the database, the cache shouldn't be large.
        # HINT; Account for processing time, don't expire entries that are (long time) queued for immich processing!
        "--vfs-cache-max-age=1h" # Default
        # Check for stale objects every hour (default is every minute)
        # This interval is changed to print less VFS cache cleanup log messages
        "--vfs-cache-poll-interval=1h"
        # ERROR; Basic operations like statfs hang when the remote is offline, and it's not possible to instruct mergerFS to ignore
        # or redirect filesystem requests
        #
        # Set total disk size statically to prevent immich hanging
        "--vfs-disk-space-total-size=5T" # 5 Terabytes
        # ERROR; Free space is misreported at the top of mergerfs!
        #
        # Read the objects (from source) in small chunks because of low bandwith (~5mbps).
        # Reading small chunks keeps sftp connection snappy.
        "--vfs-read-chunk-size=500K"
        # Chunk doubling size limit (from source). Unused when parallel streams are in use for downloading, see below
        "--vfs-read-chunk-size-limit=500K"
        # The number of parallel streams to read (from source) at simultanuously
        "--vfs-read-chunk-streams=4"
        # Number of parallel streams to write (to source) simultanuously
        "--transfers=4" # Default
        #
        # WARN; The 'pictures' directory is pre-created by systemd-tmpfiles to have a validation condition. RClone by default errors
        # when a filesystem node is not a directory node or not empty.
        # Tell _rclone_ to skip mount-dir validation!
        "--allow-non-empty"
        "--allow-other"
        "--uid=${toString config.users.users.immich.uid}"
        "--gid=${toString config.users.groups.immich.gid}"
        "--umask=0022"
      ];

      ExecStop = "/run/wrappers/bin/fusermount -u /mnt/remote/buddy-sftp";
      # Clears VFS caches
      ExecReload = "/run/booted-system/sw/bin/kill -SIGHUP $MAINPID";

      RuntimeDirectory = [ "rclone-ftp/buddy" ];
      TimeoutStartSec = 16;
      TimeoutStopSec = 180;
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  programs.fuse = {
    # NOTE; Should put fuse2 and fuse3 on system PATH
    enable = true;
    userAllowOther = false;
  };

  environment.systemPackages = [
    pkgs.e2fsprogs # chattr
  ];
}
