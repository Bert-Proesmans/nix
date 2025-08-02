{ ... }:
{
  # In this file you'll find changes that are communicated upstream but not yet incorporated
  # into the standard set of dependencies.
  # Expect this file to dissapear in time.

  services.immich = {
    redis.host = "/run/redis-immich/redis.sock";
  };

  systemd.services.immich-server = {
    after = [
      "redis-immich.service"
      "postgresql.service"
    ];
  };

  systemd.services.immich-machine-learning = {
    after = [
      "redis-immich.service"
      "postgresql.service"
    ];
  };
}
