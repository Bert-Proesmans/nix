{
  lib,
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
    "/mnt".d = {
      user = "root";
      group = "root";
      mode = "0555"; # a+rx
    };

    "/var/cache/rclone".d = {
      user = "root";
      group = "root";
      mode = "0700"; # u+rwx
    };
  };

  systemd.mounts = [
    {
      description = "Mount buddy pictures to local filesystem";
      wants = [
        "network.target"
        "tailscaled-autoconnect.service"
      ];
      after = [
        "network.target"
        "tailscaled-autoconnect.service"
      ];
      what = "buddy:/pictures";
      where = "/mnt/buddy/pictures";
      type = "rclone";
      options = lib.concatStringsSep "," [
        "config=/etc/rclone.config"
        "contimeout=60s" # SFTP session (/socket) timeout
        "timeout=60s" # I/O timeout -> I/O operations hang indefinite otherwise
        # NOTE; Pre-created directory.
        # NOTE; Having multiple rclone processes working on the same cache directory should be no issue (while the processes are running
        # in the same security context!)
        "cache-dir=/var/cache/rclone"
        "vfs-cache-mode=writes"
        "daemon-wait=60s" # Startup time
        # Don't optimize VFS cache yet..
        # REF; https://github.com/rclone/rclone/blob/master/vfs/vfs.md
        "args2env" # Pass mount arguments below to mount helper!
        "rw"
        "allow_other"
      ];
      unitConfig = { };
      # Time to wait before SIGKILL
      # NOTE; Should match with rclone timeout settings
      mountConfig.TimeoutSec = 61;
    }
  ];

  systemd.automounts = [
    {
      # Since /mnt/buddy/pictures is not part of local-fs, add an automount so it gets ordered between services anyway.
      description = "Automount for /mnt/buddy/pictures";
      wantedBy = [ "multi-user.target" ];
      where = "/mnt/buddy/pictures";
    }
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
