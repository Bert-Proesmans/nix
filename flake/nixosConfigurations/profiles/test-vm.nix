{ lib, ... }:
let
  mkVMDefault = lib.mkOverride 900;
in
{
  virtualisation.cores = 2;
  virtualisation.memorySize = 2048;
  # WORKAROUND; nixos-generators sets disksize to null without specialArgs
  # REF; https://github.com/nix-community/nixos-generators/issues/306
  virtualisation.diskSize = lib.mkForce 1024;
  virtualisation.graphics = false;

  # Configure networking
  networking.useDHCP = mkVMDefault false;
  networking.interfaces.eth0.useDHCP = mkVMDefault true;
  networking.firewall.enable = mkVMDefault false;

  # Create user "test"
  users.users.test.isNormalUser = true;
  services.getty.autologinUser = mkVMDefault "test";

  # Enable passwordless ‘sudo’ for the "test" user
  users.users.test.extraGroups = [ "wheel" ];
  security.sudo.wheelNeedsPassword = mkVMDefault false;

  # Provide basic shortcuts to the user
  services.getty.helpLine = mkVMDefault ''
    Type Ctrl-a c to switch to the qemu console
    and `quit` to stop the VM. `cont` will drop
    out of the console and resume the VM.
  '';
}
