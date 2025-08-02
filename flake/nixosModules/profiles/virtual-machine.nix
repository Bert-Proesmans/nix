{ ... }:
{
  # EFI boot!
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;

  # Cleaning tmp directory not required if it's a tmpfs
  # Enabling tmpfs for tmp also prevents additional SSD writes
  boot.tmp.cleanOnBoot = false;
  boot.tmp.useTmpfs = true;
}
