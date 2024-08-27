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
}
