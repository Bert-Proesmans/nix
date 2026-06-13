{ lib, flake, ... }:
{
  imports = [
    ./backup-landing.nix
    ./backup.nix
    ./certificates.nix
    ./computer-backup.nix
    ./database.nix
    ./disks.nix
    ./dns.nix
    ./filesystems.nix
    ./hardware-configuration.nix
    ./identity.nix
    ./mail-transfer.nix
    ./pictures-provision.nix
    ./private-network.nix
    ./storage-provision.nix
    ./tls-termination.nix
    # ./web-security.nix
    flake.profiles.hypervisor
  ];

  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.sopsSecrets.enable = true;
  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  proesmans.sopsSecrets.sshHostkeyControl.enable = true;
  proesmans.home-manager.enable = true;
  users.mutableUsers = false;

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
      "kvm" # Interact with forwarded VSOCK files
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOs8kDMMm/QFeELt79EG9akdfX7dlfRuTezwVEqbPsM bert@B-PC"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQ6i6epTE7G73/fZT1V5iBIEwBS/mpMoOfv3OOo+cMr azuread\\bertproesmans@epower-518172"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "resilio-sync"
    ];

  systemd.services.auto-shutdown = {
    description = "Automatically shutdown to save energy.";
    startAt = "Mon..Fri 06:00:00";
    script = ''
      # ERROR; Trying to be clever and manually calling the poweroff service/targets will not (always) cause the system to properly poweroff!
      # REF; https://www.freedesktop.org/software/systemd/man/latest/systemd-halt.service.html
      systemctl poweroff
    '';
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
