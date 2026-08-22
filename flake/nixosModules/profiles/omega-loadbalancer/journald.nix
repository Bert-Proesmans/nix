{ ... }: {
  services.journald = {
    storage = "volatile";
    extraConfig = ''
      SystemMaxUse=256M    # Maximum journal size on persistent storage (unused)
      RuntimeMaxUse=64M    # Maximum journal size in volatile storage
      MaxFileSec=1week     # Maximum time to retain log files
    '';
  };
}
