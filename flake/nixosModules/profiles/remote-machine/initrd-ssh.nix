{ config, ... }:
let
  sshPackage = config.programs.ssh.package;
in
{
  assertions = [
    {
      assertion = config.boot.initrd.systemd.enable == true;
      message = ''
        Boot unlock makes use of systemd in initial ramdisk, but systemd is not enabled!
        To fix this, set option `boot.initrd.systemd.enable = true`.
      '';
    }
  ];

  boot.initrd = {
    systemd = {
      # NOTE; The system network configuration should have been captured for initrd too
      # network = {};
      storePaths = [
        # Required for initrd ssh service
        "${sshPackage}/bin/ssh-keygen"
      ];

      services.sshd = {
        # Updates the sshd service to generate a new hostkey on-demand
        preStart = ''
          ${sshPackage}/bin/ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
        '';
      };
    };

    network = {
      enable = true;
      ssh = {
        enable = true;
        # To prevent ssh clients from freaking out because a different host key is used,
        # a different port for ssh is useful (assuming the same host has also a regular sshd running)
        #
        # WARN; Port must be the same as defined in tasks.py:unlock()!
        port = 23;
        hostKeys = [
          # Doesn't work for shit, weird documentation and general lack of affordance.
          # Key is provided out-of-band.
          # SEEALSO; boot.initrd.systemd.services.sshd
          # SEEALSO; boot.initrd.network.ssh.extraConfig
        ];
        ignoreEmptyHostKeys = true;
        # Could alternatively have used argument "-h" when starting sshd
        # SEEALSO; boot.initrd.systemd.services.sshd
        extraConfig = ''
          HostKey /etc/ssh/ssh_host_ed25519_key
        '';
        authorizedKeys = [
          # After login and tty construction, switch to- and block on completion of the initrd flow. AKA wait until initrd.target
          # activates, which requires password prompt completion.
          # The password prompts use "systemd-ask-password" to block the boot continuation. Systemd executes systemd-tty-ask-password-agent
          # on each tty so the password(s) can be provided interactively. The SSH session also has a virtual tty now. AKA upon login
          # you're asked to enter the password(s) and the session will reset after succesful unlock.
          #
          # NOTE; systemctl default == systemctl isolate default.target
          # NOTE; the unit systemd-ask-password-console.service is responsible for launching the password agent on tty's
          "command=\"systemctl default\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
        ];
      };
    };
  };
}
