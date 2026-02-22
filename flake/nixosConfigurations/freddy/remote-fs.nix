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
  environment.etc."rclone.config" = {
    # NOTE; Config holds no secret values, only path references to them
    text = ''
      [buddy]
        type = sftp
        host = ${fqdn-buddy}
        user = freddy
        key_file = ${config.sops.secrets."buddy_ssh".path}
        known_hosts_file = /etc/ssh/ssh_known_hosts
        # Settings below are required to fix warnings about config file not writeable
        shell_type = unix
        md5sum_command = md5sum
        sha1_command = sha1sum
    '';
  };

  systemd.tmpfiles.settings."10-remote_fs" = {
    "/var/cache/rclone".d = {
      user = "root";
      group = "root";
      mode = "0700"; # u+rwx
    };

    "/mnt/remote".d = {
      # ERROR; Must restrict this directory because otherwise every user is allowed to read contents of the buddy host!
      user = "root";
      group = "root";
      mode = "0000";
    };
    "/mnt/remote/buddy-sftp".d = { };
    # NOTE; Premount directory creation necessary for mergerfs tags to improve merger intelligence
    "/mnt/remote/buddy-sftp/chroot/pictures".d = { };
    "/mnt/remote/buddy-sftp/chroot/pictures-external".d = { };
  };

  systemd.mounts = [
    {
      # ERROR; A 'single computer'-mount over sftp has a flaw that owner:group is fabricated on demand, there exist no _real_ inodes
      # to store custom permissions from the view of freddy!
      # SFTP has no linux permission model, there is single-user and modification bits.
      #
      # NOTE; The mount is forced to be owned by the immich user (freddy view), but actual permissions are validated on buddy.
      description = "Mount buddy to local filesystem";
      conflicts = [ "umount.target" ];
      # Need these units but won't queue a startjob if they aren't active
      requisite = [ config.systemd.targets."buddy-online".name ];
      wants = [
        "merger-fs-pre@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/chroot/pictures"}.service"
        # ERROR; SFTP carrier does not support file attributes, marker cannot be set!
        # "merger-fs-post@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp"}.service"
      ];
      after = [
        "systemd-tmpfiles-setup.service"
        "merger-fs-pre@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/chroot/pictures"}.service"
        config.systemd.targets."buddy-online".name
      ];
      before = [
        # See note above
        # "merger-fs-post@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp"}.service"
      ];
      what = "buddy:/";
      where = "/mnt/remote/buddy-sftp";
      type = "rclone";
      options = lib.concatStringsSep "," [
        # NOTE; Daemon mode doesn't produce any interesting logs!
        # HINT; Use logfile argument to store operational logging data
        # "vv" # DEBUG
        "config=/etc/rclone.config"
        "contimeout=60s" # SFTP session (/socket) timeout
        "timeout=15s" # I/O timeout -> I/O operations hang indefinite otherwise
        # NOTE; Pre-created directory.
        # ERROR; Do not reuse the cache directory between rclone processes handling the same remotes, this clobbers the cache!
        "cache-dir=/var/cache/rclone"
        "vfs-cache-mode=writes"
        # File open/-read cache is allowed get to around 20GB large.
        # NOTE; Files with open handle are not evicted from cache.
        # NOTE; Cache objects expire (see vfs-cache-max-age)!
        "vfs-cache-max-size=10G"
        # NOTE; Since most useful operations are handled by the database, the cache shouldn't be large.
        # HINT; Account for processing time, don't expire entries that are (long time) queued for immich processing!
        "vfs-cache-max-age=1h" # Default
        # ERROR; Basic operations like statfs hang when the remote is offline, and it's not possible to instruct mergerFS to ignore
        # or redirect filesystem requests
        #
        # Set total disk size statically to prevent immich hanging
        "vfs-disk-space-total-size=5T" # 5 Terabytes
        # ERROR; Free space is misreported at the top of mergerfs!
        #
        # Don't optimize VFS cache yet..
        # REF; https://github.com/rclone/rclone/blob/master/vfs/vfs.md
        "daemon-wait=15s" # Startup time
        #
        # WARN; The 'pictures' directory is pre-created by systemd-tmpfiles to have a validation condition. RClone by default errors
        # when a filesystem node is not a directory node or not empty.
        # Tell _rclone_ to skip mount-dir validation!
        "allow-non-empty"
        "args2env" # Do not pass config to fuse process as arguments (leaks into process monitors)!
        "rw"
        "allow_other"
        "uid=${config.users.users.immich.name}"
        "gid=${config.users.groups.immich.name}"
        "umask=0022"
      ];
      unitConfig.DefaultDependencies = false;
      # Time to wait before SIGKILL
      # NOTE; Should match with rclone timeout settings
      mountConfig.TimeoutSec = 16;
    }
  ];

  systemd.automounts = [
    # ERROR; Automount seems to be too eager and blocks various operations. MergerFS also causes userspace hangs during toplevel operations.
    # Better to explicitly mount when server comes online instead.
    # {
    #   description = "Automount for /mnt/remote/buddy-sftp/pictures";
    #   wantedBy = [ "multi-user.target" ];
    #   where = "/mnt/remote/buddy-sftp/pictures";
    # }
  ];

  systemd.services."merger-fs-pre@" = {
    description = "Landing zone prep for %I";
    conflicts = [ "shutdown.target" ];
    before = [ "shutdown.target" ];
    path = [
      pkgs.util-linux # mountpoint
      pkgs.attr # sefattr
    ];
    enableStrictShellChecks = true;
    scriptArgs = "'%I'";
    script = ''
      # ERROR; Path could have dropped root slash during conversion!
      location="/$1"

      # Code must run _before_ anything is mounted at $location
      mountpoint --quiet "$location" && exit 1

      setfattr -n user.mergerfs.branch_mounts_here "$location"
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = false;
    unitConfig.DefaultDependencies = false;
  };

  systemd.services."merger-fs-post@" = {
    description = "Mount finalization for %I";
    conflicts = [ "shutdown.target" ];
    before = [ "shutdown.target" ];
    path = [
      pkgs.attr # setfattr
    ];
    enableStrictShellChecks = true;
    scriptArgs = "'%I'";
    script = ''
      # ERROR; Path could have dropped root slash during conversion!
      location="/$1"

      # The directory is marked for mergerfs to differentiate mounted/to be mounted.
      setfattr --name user.mergerfs.branch "$location"
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = false;
    unitConfig.DefaultDependencies = false;
  };

  programs.fuse = {
    # NOTE; Should put fuse2 and fuse3 on system PATH
    enable = true;
    userAllowOther = false;
  };

  environment.systemPackages = [
    pkgs.rclone # mount.rclone on path for systemd mount
    pkgs.e2fsprogs # chattr
  ];
}
