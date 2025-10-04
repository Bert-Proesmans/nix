{ ... }:
{
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
}
