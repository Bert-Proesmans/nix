{
  lib,
  pkgs,
  config,
  ...
}:
{
  networking.domain = "alpha.proesmans.eu";

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];

  environment.systemPackages = [
    pkgs.curl
    pkgs.socat
    pkgs.tcpdump
    pkgs.python3
    pkgs.nmap # ncat
    pkgs.netcat-openbsd
  ];

  security.acme = {
    # Self-signed certs
    acceptTerms = true;
    defaults = {
      email = "bproesmans@hotmail.com";
    };
  };

  systemd.services."acme-photos.alpha.proesmans.eu".serviceConfig.ExecStart =
    lib.mkForce "${pkgs.coreutils}/bin/true";

  # Override this service for fun and debug profit
  systemd.services."test".serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";

  # nixpkgs.overlays = [
  #   (final: prev:
  #     let
  #       machine-learning-upstream = prev.immich.passthru.machine-learning;
  #     in
  #     {
  #       immich = prev.unsock.wrap (prev.immich.overrideAttrs (old: {
  #         # WARN; Assume upstream has properly tested for quicker build completion
  #         doCheck = false;
  #         passthru = old.passthru // {
  #           # ERROR; 'Immich machine learning' is pulled from the passed through property of 'Immich'
  #           machine-learning = final.immich-machine-learning;
  #         };
  #       }));
  #       # immich-machine-learning = prev.unsock.wrap (prev.immich-machine-learning.overrideAttrs (old: {
  #       #   # WARN; Assume upstream has properly tested for quicker build completion
  #       #   doCheck = false;
  #       # }));
  #       immich-machine-learning = prev.unsock.wrap (machine-learning-upstream.overrideAttrs (old: {
  #         # WARN; Assume upstream has properly tested for quicker build completion
  #         doCheck = false;
  #       }));
  #     })
  # ];

  services.immich = {
    enable = true;
    # WARN; Host IP matches unsock configuration!
    host = "127.175.0.0";
    port = 8080;
    openFirewall = false;
    mediaLocation = "/var/lib/immich";

    environment = {
      IMMICH_LOG_LEVEL = "log";
      # The timezone used for interpreting date/timestamps without time zone indicator
      TZ = "Europe/Brussels";
    };

    machine-learning = {
      environment = { };
    };
  };

  systemd.services.immich-server = {
    unsock = {
      enable = false;
      tweaks.accept-convert-vsock = true;
      proxies = [
        {
          match.port = config.services.immich.port;
          to.vsock.cid = -1; # Bind to loopback
          to.vsock.port = 8080;
        }
        # NOTE; No proxy for machine learning, i don't care if both server modules talk to each other
        # over loopback AF_INET
      ];
    };

    serviceConfig = {
      # ERROR; Must manually open up the usage of VSOCKs.
      RestrictAddressFamilies = [ "AF_VSOCK" ];
    };
  };

  systemd.services.immich-machine-learning = {
    environment = {
      # WARN; The machine learning server takes the same environment variables as the frontend server!
      # These environment variable names could cause confusion!
      # IMMICH_HOST = lib.mkForce config.services.immich.host;
      # IMMICH_PORT = lib.mkForce (toString 5555);
    };
    unsock = {
      enable = false;
      socket-directory = config.systemd.services.immich-server.unsock.socket-directory;
      tweaks.accept-convert-vsock = true;
      proxies = [
        {
          match.port = config.services.immich.port;
          to.vsock.cid = -1; # Bind to loopback
          to.vsock.port = 8080;
        }
        # NOTE; No proxy for machine learning, i don't care if both server modules talk to each other
        # over loopback AF_INET
      ];
    };

    serviceConfig = {
      # ERROR; Must manually open up the usage of VSOCKs.
      RestrictAddressFamilies = [ "AF_VSOCK" ];
    };
  };

  services.postgresql = {
    enableJIT = true;
    enableTCPIP = false;
    package = pkgs.postgresql_15_jit;
  };

  systemd.services.postgresql.serviceConfig = { };

  proesmans.vsock-proxy.proxies = [
    {
      description = "Connect VSOCK to AF_INET for immich service";
      listen.vsock.cid = -1; # Binds to localhost
      listen.port = 8080;
      transmit.tcp.ip = config.services.immich.host;
      transmit.port = config.services.immich.port;
    }
  ];

  system.stateVersion = "24.05";
}
