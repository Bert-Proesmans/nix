{
  lib,
  flake,
  pkgs,
  ...
}:
{
  imports = [
    ./disks.nix
    ./hardware-configuration.nix
    flake.profiles.omega-loadbalancer
    flake.profiles.remote-machine
  ];

  # Slows down write operations considerably
  nix.settings.auto-optimise-store = lib.mkForce false;

  # Setup runtime secrets and corresponding ssh host key
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.enable = true;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "rescue-tftpd";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.rs-tftpd
      ];
      text = ''
        # NOTE; Provide .efi executables to rescue other virtual machines in the VPS
        #
        # The images below are specific to Oracle cloud.
        # curl -L https://github.com/netbootxyz/netboot.xyz/releases/latest/download/netboot.xyz-arm64.efi -o netboot.xyz-arm64.efi
        # curl -L https://github.com/netbootxyz/netboot.xyz/releases/latest/download/netboot.xyz-snp.efi -o netboot.xyz-snp.efi

        SRC_DIR=$(mktemp -d)
        PORT="6969"

        echo "Launching TFTP daemon serving files from directory: $SRC_DIR"

        # Open firewall with;
        # sudo iptables -I INPUT 1 -s 10.0.84.0/24 -p tcp --dport 6969 -j ACCEPT
        # sudo iptables -I INPUT 1 -s 10.0.84.0/24 -p udp --dport 6969 -j ACCEPT
        #
        # Verify with;
        # sudo iptables -L INPUT -n --line-numbers
        #
        # NOTE; The above commands do not persist across a reboot!
        echo "WARNING; Make sure to allow incoming connections on port $PORT"

        # WARN; Must bind to port >1024 to allow user-bind
        tftpd --ip-address 0.0.0.0 --port "$PORT" --directory "$SRC_DIR" --read-only
      '';
    })
  ];

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "25.05";
}
