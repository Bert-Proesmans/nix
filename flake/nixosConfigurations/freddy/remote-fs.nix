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
      description = "Mount buddy to local filesystem";
      conflicts = [ "umount.target" ];
      wants = [
        "network.target"
        "tailscaled-autoconnect.service"
        "merger-fs-pre@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
        "finalize-mount-fs@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
      ];
      after = [
        "systemd-tmpfiles-setup.service"
        "network.target"
        "tailscaled-autoconnect.service"
        "merger-fs-post@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
      ];
      before = [
        "merger-fs-post@${utils.escapeSystemdPath "/mnt/remote/buddy-sftp/pictures"}.service"
      ];
      what = "buddy:/";
      where = "/mnt/remote/buddy-sftp";
      type = "rclone";
      options = lib.concatStringsSep "," [
        "vv" # DEBUG
        "config=/etc/rclone.config"
        "contimeout=60s" # SFTP session (/socket) timeout
        "timeout=15s" # I/O timeout -> I/O operations hang indefinite otherwise
        # NOTE; Pre-created directory.
        # NOTE; Having multiple rclone processes working on the same cache directory should be no issue (while the processes are running
        # in the same security context!)
        "cache-dir=/var/cache/rclone"
        "vfs-cache-mode=writes"
        "daemon-wait=15s" # Startup time
        # Don't optimize VFS cache yet..
        # REF; https://github.com/rclone/rclone/blob/master/vfs/vfs.md
        "args2env" # Pass mount arguments below to mount helper!
        "rw"
        "allow_other"
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

  programs.ssh.knownHosts = {
    "buddy".hostNames = [ fqdn-buddy ];
    "buddy".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICj+WUMawU/pZ8yGJNeoL8vsc5B+LOi4Y7JTCG4bv4vp";
  };

  # Make sure the fqdn of buddy resolves through tailscale!
  networking.hosts."${ip-buddy}" = [ fqdn-buddy ];

  environment.systemPackages = [
    # Following packages must exist at system path for .mount unit files to work
    # NOTE; Couldn't I just add these to systemd package set?
    pkgs.fuse3 # fuse defaults to fuse2
    pkgs.rclone
  ];
}
