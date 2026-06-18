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

  services.pixiecore =
    let
      miniHost = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (
            {
              config,
              pkgs,
              lib,
              modulesPath,
              ...
            }:
            {
              imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];
              config = {
                system.stateVersion = config.system.nixos.release;

                # make it easier to debug boot failures
                boot.initrd.systemd.emergencyAccess = true;

                # enable zswap to help with low memory systems
                boot.kernelParams = [
                  "zswap.enabled=1"
                  "zswap.max_pool_percent=50"
                  "zswap.compressor=zstd"
                  # recommended for systems with little memory
                  "zswap.zpool=zsmalloc"
                ];

                netboot.squashfsCompression = "zstd -Xcompression-level 6";
                networking.wireless.enable = lib.mkForce false;
                documentation.enable = false;
                documentation.man.man-db.enable = false;
                documentation.nixos.enable = false;

                # Drop ~400MB firmware blobs from nix/store, but this will make the host not boot on bare-metal!
                # hardware.enableRedistributableFirmware = lib.mkForce false;

                # ERROR; The mkForce is required to _reset_ the lists to empty! While the default
                # behaviour is to make a union of all list components!
                # No GCC toolchain
                system.extraDependencies = lib.mkForce [ ];
                # Remove default packages not required for a bootable system
                environment.defaultPackages = lib.mkForce [ ];
                # prevents shipping nixpkgs, unnecessary if system is evaluated externally
                nix.registry = lib.mkForce { };
                system.installer.channel.enable = false;

                environment.ldso32 = null;

                services.openssh = {
                  enable = true;
                  openFirewall = true;

                  settings = {
                    PasswordAuthentication = false;
                    KbdInteractiveAuthentication = false;
                    PermitRootLogin = "prohibit-password";
                  };
                };

                users.users.root.openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOs8kDMMm/QFeELt79EG9akdfX7dlfRuTezwVEqbPsM bert@B-PC"
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQ6i6epTE7G73/fZT1V5iBIEwBS/mpMoOfv3OOo+cMr azuread\\bertproesmans@epower-518172"
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
                ];
              };
            }
          )
        ];
      };
      buildMiniHost = miniHost.config.system.build;
    in
    {
      enable = true;
      debug = true;
      openFirewall = true;
      dhcpNoBind = true;
      port = 8635;
      # mode = "quick";
      # quick = "xyz";
      # NOTE; Pixie will auto-boot iPXE first, then chainload the kernel and ramdisk
      mode = "boot";
      kernel = "${buildMiniHost.kernel}/bzImage";
      initrd = "${buildMiniHost.netbootRamdisk}/initrd";
      cmdLine = "init=${buildMiniHost.toplevel}/init loglevel=4";
    };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
