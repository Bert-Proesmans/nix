{ profiles, ... }: {
  imports = [ profiles.dns-server ];

  networking.domain = "alpha.proesmans.eu";

  services.openssh.hostKeys = [
    {
      path = "/data/seeds/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd.services.sshd.unitConfig.ConditionPathExists = "/data/seeds/ssh_host_ed25519_key";

  # Not much to define here, the DNS configuration is very easily profiled.
  # SEEALSO; profiles.dns-server

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
