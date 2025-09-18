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
  ];

  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.sopsSecrets.enable = true;
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;
  proesmans.home-manager.enable = true;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Make me an admin!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "wheel" # Allows sudo access
      "systemd-journal" # Read the systemd service journal without sudo
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };

  # Create builder user for remote-building
  users.users.builder = {
    isNormalUser = true;
    description = "Nix remote builder user";
    extraGroups = [ ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH8sCzJd8HMqN96YmMFRNocbng01Ct/UV+Z42EZJnsAL root(builder)@development"
    ];
  };
  nix.settings.max-jobs = 2;
  nix.settings.trusted-users = [ "builder" ];

  # Ensure a single individual build task doesn't freeze the system, without trusting the random action of the kernel
  # out-of-memory (OOM) killer.
  services.earlyoom.enable = true;
  services.earlyoom.freeMemThreshold = 2; # Percentage of total RAM

  systemd.services = {
    memory-stress = {
      enable = false;
      description = "memory-stress";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.stress-ng} --vm 1 --vm-bytes 15% --vm-hang 0";
        Restart = "always";
        Type = "exec";
      };
    };

    cpu-stress = {
      enable = false;
      description = "cpu-stress";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.stress-ng} --cpu 8 --cpu-load 15";
        Restart = "always";
        Type = "exec";
      };
    };
  };

  # Avoid TOFU MITM with github by providing their public key here.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
