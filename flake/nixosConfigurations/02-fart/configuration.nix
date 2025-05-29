{ lib, modulesPath, ... }: {
  #
  # Boot on AMD 1OCPU
  #
  # NOTE; nixos-anywhere should be able to "stream-install" as well in limited RAM circumstances. The instructions below are doing 
  # the manual work for minimal RAM impact.
  # WARN; The disko configuration will ask for a password on luks format, but interactive input during nixos-anywhere install doesn't
  # work. The process will hang forever waiting for input. To fix;
  #   - OR Run disko formatting interactively 
  #   - OR configure a keypath and upload the key as deployment argument (--disk-encryption-keys)
  #
  # 1. Configure VPS
  #   1. Choose a minimal ubuntu image
  #   2. Enter SSH pubkey
  # 2. SSH into host (ssh ubuntu@<$IP>)
  # 3. Cleanup running processes to free RAM (`top`, press e, press shift+m)
  #   1. sudo systemctl --no-block stop snapd snap* unattended-upgrades
  #   2. echo 3 | sudo tee /proc/sys/vm/drop_caches
  # 4. Kernel exec (K'exec) into nixos system
  #   1. curl -L https://github.com/nix-community/nixos-images/releases/latest/download/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz | tar -xzf- -C /tmp && sudo /tmp/kexec/run
  # 5. SSH into kexec (ssh root@<$IP>), or use console connection
  # 6. Build and copy format script of host
  #   2. nix build --no-link ./flake#nixosConfigurations.02-fart.config.system.build.diskoScript
  #   1. DISKO="$(nix path-info ./flake#nixosConfigurations.02-fart.config.system.build.diskoScript)"
  #   3. nix copy --substitute-on-destination --to "ssh-ng://root@$IP" "$DISKO" --no-check-sigs
  # 7. Execute format script
  #   1. ssh "root@$IP" "$DISKO"
  # NOTE; Disko leaves the new root filesystem mounted at /mnt
  # 8. Install the nixos configuration
  #   1. nix build --no-link ./flake#nixosConfigurations.02-fart.config.system.build.toplevel
  #   2. HOST="$(nix path-info ./flake#nixosConfigurations.02-fart.config.system.build.toplevel)"
  #   WARN; nixos-install has two modes; 1. build the target system from sources (in nix store) / 2. copy built system from a local nix store
  #         But we cannot build on FART and we're running completely from RAM (aka no persistent attached storage to boot NixOS from).
  #         So;
  #         - The built system is copied into /mnt(/nix) using the remote-store feature.
  #         - nixos-install is called with a root argument to assume '/nix/store' as '/mnt/nix/store' and install correctly
  #   ERROR; The nix copy operation could hang due to kernel swapping, if it looks like progress stalled cancel the command and wait
  #          for the swapping to end. Then execute the same command again.
  #   3. nix copy --substitute-on-destination --to "ssh-ng://root@$IP?remote-store=/mnt&" "$HOST" --no-check-sigs
  #   4. ssh "root@$IP" nixos-install --no-root-password --no-channel-copy --root /mnt --system "$HOST"
  # 9. Reboot system; ssh "root@$IP" reboot
  # DONE.

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
  ];

  nixpkgs.hostPlatform = lib.systems.examples.gnu64;
  hardware.enableRedistributableFirmware = true;
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.tmp.useTmpfs = false; # Only have 1G RAM
  boot.tmp.cleanOnBoot = true;

  networking.useDHCP = true;
  networking.useNetworkd = true;

  # Slows down write operations considerably
  nix.settings.auto-optimise-store = lib.mkForce false;

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            encryptedSwap = {
              size = "2G"; # Only have 1G RAM
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

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

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "25.05";
}
