{ lib, config, ... }: {
  # Force be-latin keymap (= BE-AZERTY-ISO)
  console.keyMap = lib.mkDefault "be-latin1";
  time.timeZone = lib.mkDefault "Etc/UTC";

  # Append all user ssh keys to the root user
  users.users.root.openssh.authorizedKeys.keys = lib.pipe config.users.users [
    (lib.attrsets.filterAttrs (_: user: user.isNormalUser))
    (lib.mapAttrsToList (_: user: user.openssh.authorizedKeys.keys))
    (lib.lists.flatten)
  ];

  # Fallback quickly if substituters are not available.
  nix.settings.connect-timeout = lib.mkForce 5;
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # The default at 10 is rarely enough.
  nix.settings.log-lines = lib.mkForce 25;
  # Dirty git repo warnings become tiresome really quickly...
  nix.settings.warn-dirty = lib.mkForce false;

  # Faster and (almost) equally as good compression
  isoImage.squashfsCompression = lib.mkForce "zstd -Xcompression-level 15";
  # Ensure sshd starts at boot
  systemd.services.sshd.wantedBy = [ "multi-user.target" ];
  # No Wifi
  networking.wireless.enable = lib.mkForce false;
  # No docs
  documentation.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;

  # Drop ~400MB firmware blobs from nix/store, but this will make the host not boot on bare-metal!
  # hardware.enableRedistributableFirmware = lib.mkForce false;
  # ERROR; The mkForce is required to _reset_ the lists to empty! While the default
  # behaviour is to make a union of all list components!
  # No GCC toolchain
  system.extraDependencies = lib.mkForce [ ];
  # Remove default packages not required for a bootable system
  environment.defaultPackages = lib.mkForce [ ];
}
