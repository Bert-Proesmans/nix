{ ... }:
{
  # Make me an admin!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "wheel" # Allows sudo access
      "systemd-journal" # Read the systemd service journal without sudo
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQ6i6epTE7G73/fZT1V5iBIEwBS/mpMoOfv3OOo+cMr azuread\\bertproesmans@epower-518172"
    ];
  };
}
