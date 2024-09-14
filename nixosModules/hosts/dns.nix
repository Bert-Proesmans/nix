{ special, ... }: {
  imports = [ special.profiles.dns-server ];

  networking.domain = "alpha.proesmans.eu";

  # Not much to define here, the DNS configuration is very easily profiled.
  # SEEALSO; profiles.dns-server

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
