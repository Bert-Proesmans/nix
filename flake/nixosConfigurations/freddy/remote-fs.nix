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
  };

  systemd.services."prep-mount-fs@" = {
    description = "Landing zone prep for %I";
    conflicts = [ "shutdown.target" ];
    before = [ "shutdown.target" ];
    after = [ "sysinit.target" ];
    path = [
      pkgs.util-linux # mountpoint
      pkgs.coreutils # chown/chmod
      pkgs.attr # sefattr
      pkgs.e2fsprogs # chattr
    ];
    enableStrictShellChecks = true;
    scriptArgs = "'%I'";
    script = ''
      location="$1"

      # Code must run _before_ anything is mounted at $location
      mountpoint --quiet "$location" && exit 0

      # Create directory and make it immutable for all users and systems.
      # The directory is marked for mergerfs to differentiate mounted/to be mounted.

      mkdir --parents "$location"
      chown root:root "$location"
      chmod 0000 "$location"
      setfattr -n user.mergerfs.branch_mounts_here "$location"
      chattr +i "$location"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      # Run as root
    };
    unitConfig.DefaultDependencies = false;
  };

  systemd.services."finalize-mount-fs@" = {
    description = "Mount finalization for %I";
    conflicts = [ "shutdown.target" ];
    before = [ "shutdown.target" ];
    path = [
      pkgs.util-linux # mountpoint
      pkgs.coreutils # chown/chmod
      pkgs.attr # setfattr
    ];
    enableStrictShellChecks = true;
    scriptArgs = "'%I'";
    script = ''
      location="$1"

      # Code must run _after_ the mount at $location
      mountpoint --quiet "$location" || exit 0

      # Default open/simple permissions for any mount type.
      # The directory is marked for mergerfs to differentiate mounted/to be mounted.

      chown root:root "$location"
      chmod 1777 "$location"
      setfattr -n user.mergerfs.branch "$location"
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
      description = "Mount buddy pictures to local filesystem";
      conflicts = [ "umount.target" ];
      wants = [
        "network.target"
        "tailscaled-autoconnect.service"
        "prep-mount-fs@${utils.escapeSystemdPath "/mnt/remote/pictures-buddy-sftp"}.service"
        "finalize-mount-fs@${utils.escapeSystemdPath "/mnt/remote/pictures-buddy-sftp"}.service"
      ];
      after = [
        "sysinit.target" # Tempfiles creation
        "network.target"
        "tailscaled-autoconnect.service"
        "prep-mount-fs@${utils.escapeSystemdPath "/mnt/remote/pictures-buddy-sftp"}.service"
      ];
      before = [
        "finalize-mount-fs@${utils.escapeSystemdPath "/mnt/remote/pictures-buddy-sftp"}.service"
      ];
      what = "buddy:/pictures";
      where = "/mnt/remote/pictures-buddy-sftp";
      type = "rclone";
      options = lib.concatStringsSep "," [
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
    # Automount seems to be too eager and blocks various operations. Better to explicitly mount instead.
    #
    # {
    #   # Since /mnt/remote/pictures-buddy-sftp is not part of local-fs, add an automount so it gets ordered between services anyway.
    #   description = "Automount for /mnt/remote/pictures-buddy-sftp";
    #   wantedBy = [ "multi-user.target" ];
    #   where = "/mnt/remote/pictures-buddy-sftp";
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
