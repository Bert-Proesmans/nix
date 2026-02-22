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
in
{
  systemd.targets.chroot-tree = {
    description = "SSH chroot tree lifecycle";
  };

  systemd.services.chroot-tree-builder = {
    description = "Construct immutable chroot for SSH";
    before = [
      "shutdown.target"
      config.systemd.targets.chroot-tree.name
    ];
    requiredBy = [ config.systemd.targets.chroot-tree.name ];
    partOf = [ config.systemd.targets.chroot-tree.name ];
    conflicts = [ "shutdown.target" ];

    enableStrictShellChecks = true;
    path = [
      pkgs.e2fsprogs # chattr
      pkgs.coreutils # install
    ];
    script = ''
      # ERROR; Sub mounts should not be running at this point!

      # unlock tree if exists
      if [ -d /chroot ]; then
        chattr -R -i /chroot || true
      fi

      install -d -m0755 -o root -g root /chroot
      install -d -m0000 -o root -g root /chroot/pictures
      install -d -m0000 -o root -g root /chroot/pictures-external

      chattr +i /chroot
      chattr +i /chroot/pictures
      chattr +i /chroot/pictures-external
    '';

    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = "yes";
    unitConfig.DefaultDependencies = false;
  };

  # Freddy target
  users.users.freddy = {
    # Allow interactive logon
    isNormalUser = true;
    description = "Storage mounting over network as Freddy";
    # NOTE; Relative to SSH chroot!
    home = "/";
    createHome = false;
    group = config.users.groups."freddy".name;
    extraGroups = [
      config.users.groups."sftpusers".name
      config.users.groups."pictures".name
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZc+ep5FbHyRSQSmQRjln4fy8NZ/mnOHtw2e3W123WW root@freddy"
    ];
  };
  users.groups.freddy = { };
  users.groups.sftpusers = { };

  systemd.mounts = [
    # Immich pictures directories are mounted in file pictures-provision.nix
  ];

  services.openssh = {
    allowSFTP = true;
    # WARN; Built-in sftp server so special bind-mounting isn't required
    sftpServerExecutable = "internal-sftp";
    sftpFlags = [
      "-f AUTH" # Facility for logs with sensitive data
      "-l INFO" # Log SFTP commands
    ];
    # TODO; Restrict user sessions of users remoting in!
  };

  environment.systemPackages = [
    pkgs.e2fsprogs # chattr
  ];
}
