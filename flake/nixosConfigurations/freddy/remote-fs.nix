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
    "/var/cache/rclone".d = {
      user = "root";
      group = "root";
      mode = "0700"; # u+rwx
    };

    "/mnt".d = {
      user = "root";
      group = "root";
      mode = "0555"; # a+rx
    };

    "/mnt/buddy".d = {
      user = "root";
      group = "root";
      mode = "0500"; # u+rx
    };
  };

  systemd.mounts = [
    {
      wantedBy = [ "default.target" ];
      requires = [ "tailscaled.service" ];
      after = [
        "systemd-tmpfiles-setup.service"
        "tailscaled.service"
      ];
      what = "buddy:pictures";
      where = "/mnt/buddy/pictures";
      type = "rclone";
      options = lib.concatStringsSep "," [
        "config=/etc/rclone.config"
        # NOTE; Pre-created directory.
        # NOTE; Having multiple rclone processes working on the same cache directory should be no issue (while the processes are running
        # in the same security context!)
        "cache-dir=/var/cache/rclone"
        "vfs-cache-mode=writes"
        "daemon-wait=60s"
        # Don't optimize VFS cache yet..
        # REF; https://github.com/rclone/rclone/blob/master/vfs/vfs.md
        "args2env" # Pass mount arguments below to mount helper!
        "rw"
        "allow_other"
      ];
      unitConfig = { };
      mountConfig = {
        # Amount of seconds to wait before retrying a failure
        # NOTE; Should match with rclone setting daemon-wait
        TimeoutSec = "61s";
      };
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
    pkgs.rclone # For sftp mounting
  ];
}
