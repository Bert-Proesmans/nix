[
  {
    name = "bertp/kanidm-bruteforce";
    description = "Detect kanidm brute-force attempts";
    debug = true; # DEBUG
    filter = "evt.Meta.log_type == 'kanidm_authfail'";
    groupby = "evt.Meta.source_ip";
    type = "leaky";
    leakspeed = "10s";
    capacity = 5;
    blackhole = "10m";
    labels = {
      remediation = true; # Perform ban
      service = "kanidm";
      behavior = "http:bruteforce";
      spoofable = 0; # Origin cannot have spoofed its IP
      confidence = 2; # False positive unlikely
    };
  }
]
