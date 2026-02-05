{
  lib,
  utils,
  pkgs,
  config,
  ...
}:
let
  ip-buddy = config.proesmans.facts.buddy.host.tailscale.address;
  fqdn-buddy = "buddy.internal.proesmans.eu";
in
{
  sops.secrets."buddy_ssh" = { };

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

    "/mnt/remote/buddy-sftp" = {
      d = {
        # REF; https://wiki.archlinux.org/title/SFTP_chroot#Setup_the_filesystem
        user = "root";
        group = "root";
        mode = "0000";
      };
      h.argument = "i"; # Immutable (chattr)
    };
    "/mnt/remote/buddy-sftp/pictures".d = {
      # Empty, only create no change
      # WARN; The mount is at /mnt/remote/buddy-sftp, and fuse seems to fail when the pictures subfolder exists.
      # The default behaviour of fuse3 should be to ignore existing data but something fails..
    };
    "/mnt/remote/buddy-sftp/pictures-external".d = {
      # Empty, only create no change
      # WARN; The mount is at /mnt/remote/buddy-sftp, and fuse seems to fail when the pictures subfolder exists.
      # The default behaviour of fuse3 should be to ignore existing data but something fails..
    };
  };

  systemd.services."merger-fs-pre@" = {
    description = "Landing zone prep for %I";
    conflicts = [ "shutdown.target" ];
    before = [ "shutdown.target" ];
    path = [
      pkgs.util-linux # mountpoint
      pkgs.coreutils # chown/chmod
      pkgs.attr # sefattr
      pkgs.e2fsprogs # chattr/lsattr
    ];
    enableStrictShellChecks = true;
    scriptArgs = "'%I'";
    script = ''
      # ERROR; Path could have dropped root slash during conversion!
      location="/$1"

      # Code must run _before_ anything is mounted at $location
      mountpoint --quiet "$location" && exit 0

      # Create directory and make it immutable for all users and systems.
      # The directory is marked for mergerfs to differentiate mounted/to be mounted.
      # REF; https://trapexit.github.io/mergerfs/latest/config/branches/#mount-points

      planned=false
      chown_do=false
      chmod_do=false
      xattr_do=false

      if [ ! -d "$location" ]; then
        # WARN; Branch shouldn't happen if we assume systemd-tmpfiles did its job!
        planned=true
        chown_do=true
        chmod_do=true
        xattr_do=true
      fi

      if [ -d "$location" ] && [ "$(stat -c '%u:%g' "$location")" != "0:0" ]; then
        chown_do=true
        planned=true
      fi

      if [ -d "$location" ] && [ "$(stat -c '%a' "$location")" != "0" ]; then
        chmod_do=true
        planned=true
      fi

      if [ -d "$location" ] &&
        ! getfattr --only-values --name user.mergerfs.branch_mounts_here "$location" >/dev/null 2>&1
      then
        xattr_do=true
        planned=true
      fi

      [ "$planned" = false ] && exit 0

      mkdir --parents "$location"

      if lsattr -l -d "$location" 2>/dev/null | grep --quiet 'immutable'; then
        chattr -i "$location"
      fi

      $chown_do && chown root:root "$location"
      $chmod_do && chmod 0000 "$location"
      $xattr_do && setfattr -n user.mergerfs.branch_mounts_here "$location"

      # Finalise with marking immutable
      chattr +i "$location"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      # Run as root
    };
    unitConfig.DefaultDependencies = false;
  };

  systemd.services."merger-fs-post@" = {
    description = "Mount finalization for %I";
    conflicts = [ "shutdown.target" ];
    before = [ "shutdown.target" ];
    path = [
      pkgs.util-linux # mountpoint
      pkgs.attr # setfattr
    ];
    enableStrictShellChecks = true;
    scriptArgs = "'%I'";
    script = ''
      # ERROR; Path could have dropped root slash during conversion!
      location="/$1"

      # Code must run _after_ the mount at $location
      mountpoint --quiet "$location" || exit 0

      # The directory is marked for mergerfs to differentiate mounted/to be mounted.
      setfattr --name user.mergerfs.branch "$location"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      # Run as root
    };
    unitConfig.DefaultDependencies = false;
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
      requisite = [
        config.systemd.targets."buddy-online".name
      ];
      wants = [
        "network.target"
        "tailscaled-autoconnect.service"
        "merger-fs-pre@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
        "merger-fs-post@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
      ];
      after = [
        "systemd-tmpfiles-setup.service"
        "network.target"
        "tailscaled-autoconnect.service"
        "merger-fs-pre@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
        config.systemd.targets."buddy-online".name
      ];
      before = [
        "merger-fs-post@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
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
    # Better to explicitly mount instead.
    # {
    #   description = "Automount for /mnt/remote/buddy-sftp/pictures";
    #   wantedBy = [ "multi-user.target" ];
    #   where = "/mnt/remote/buddy-sftp/pictures";
    # }
  ];

  systemd.targets."buddy-online" = {
    description = "Buddy is online";
  };

  systemd.services."buddy-online-tester" = {
    description = "Ping buddy";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.systemd # systemctl
      pkgs.iputils # ping
    ];
    enableStrictShellChecks = true;
    script = ''
      state="unknown"

      while true; do
        # Want 3 ping replies within 10 seconds awaiting each response for 2 seconds after request.
        if ping -c 3 -w 10 -W 2 "${config.proesmans.facts.buddy.host.tailscale.address}" >/dev/null; then
          new_state="online"
        else
          new_state="offline"
        fi

        if [ "$new_state" != "$state" ]; then
          if [ "$new_state" = "online" ]; then
            systemctl start "${config.systemd.targets.buddy-online.name}"
            echo "AVAILABLE transition" >&2
          else
            systemctl stop "${config.systemd.targets.buddy-online.name}"
            echo "OFFLINE transition" >&2
          fi

          state="$new_state"
        fi

        if [ "$state" = "online" ]; then
          # check less often when stable
          sleep 60
        else
          # retry faster when buddy is offline
          sleep 10
        fi
      done
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = 60;
    };
  };

  programs.ssh.knownHosts = {
    "buddy".hostNames = [ fqdn-buddy ];
    "buddy".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICj+WUMawU/pZ8yGJNeoL8vsc5B+LOi4Y7JTCG4bv4vp";
  };

  # Make sure the fqdn of buddy resolves through tailscale!
  networking.hosts."${ip-buddy}" = [ fqdn-buddy ];

  programs.fuse = {
    # NOTE; Should put fuse2 and fuse3 on system PATH
    enable = true;
    userAllowOther = false;
  };

  environment.systemPackages = [ pkgs.rclone ];
}
