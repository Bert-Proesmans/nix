{ profiles, ... }: {
  imports = [ profiles.dns-server ];

  networking.domain = "alpha.proesmans.eu";

  services.openssh.hostKeys = [
    {
      path = "/seeds/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd.services.sshd.unitConfig.ConditionPathExists = "/seeds/ssh_host_ed25519_key";

  # TODO

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
