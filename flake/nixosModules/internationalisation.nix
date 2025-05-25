{ config, lib, ... }:
let
  cfg = config.proesmans.internationalisation; # NOTE; en-GB
in
{
  options.proesmans.internationalisation = {
    be-azerty.enable = lib.mkEnableOption (lib.mdDoc "Enable the belgian internationalisation options");
  };

  config = lib.mkIf cfg.be-azerty.enable {
    console.keyMap = lib.mkDefault "be-latin1";

    i18n = {
      defaultLocale = lib.mkDefault "en_GB.UTF-8";
      extraLocales = [
        "en_GB.UTF-8/UTF-8"
        "nl_BE.UTF-8/UTF-8"
      ];
      extraLocaleSettings = {
        # REF; https://man.archlinux.org/man/locale.7
        LC_CTYPE = lib.mkDefault "en_GB.UTF-8";
        LC_NUMERIC = lib.mkDefault "nl_BE.UTF-8";
        LC_TIME = lib.mkDefault "nl_BE.UTF-8";
        LC_COLLATE = lib.mkDefault "en_GB.UTF-8";
        LC_MONETARY = lib.mkDefault "nl_BE.UTF-8";
        LC_MESSAGES = lib.mkDefault "en_GB.UTF-8";
        LC_PAPER = lib.mkDefault "nl_BE.UTF-8";
        LC_NAME = lib.mkDefault "nl_BE.UTF-8";
        LC_ADDRESS = lib.mkDefault "nl_BE.UTF-8";
        LC_TELEPHONE = lib.mkDefault "nl_BE.UTF-8";
        LC_MEASUREMENT = lib.mkDefault "nl_BE.UTF-8";
        LC_IDENTIFICATION = lib.mkDefault "nl_BE.UTF-8";
      };
    };
  };
}
