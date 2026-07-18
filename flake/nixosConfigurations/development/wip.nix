{ ... }: {
  services.displayManager.sddm = {
    enable = true;

    wayland = {
      enable = true;

      # default compositor is "weston", you can optionally change it to kwin
      #compositor = "kwin";
    };
  };

  programs.hyprland = {
    enable = true;
    withUWSM = true; # recommended for most users
    xwayland.enable = true; # Xwayland can be disabled.
  };

  users.users.bert-proesmans.password = "testing123";

  home-manager.users.bert-proesmans = { config, ... }: {
    programs.kitty.enable = true; # required for the default Hyprland config
    wayland.windowManager.hyprland = {
      enable = true; # enable Hyprland
      systemd.enable = false;
      # set the Hyprland and XDPH packages to null to use the ones from the NixOS module
      package = null;
      portalPackage = null;

      configType = "lua";
      settings = {
        mod._var = "SUPER";

        # decoration = {
        #   shadow_offset = "0 5";
        #   "col.shadow" = "rgba(00000099)";
        # };

        # "$mod" = "SUPER";

        # bind = [
        #   # Execute Rofi with only the SUPER key
        #   # "$mod, Super_L, exec, pkill rofi || rofi -show drun"

        #   "$mod, F, exec, firefox"

        #   # "CONTROL ALT, T, exec, wezterm"
        # ];

        # # Startup Apps
        # exec-once = [
        #   "hyprpanel"
        # ];

        # bindm = [
        #   # mouse movements
        #   "$mod, mouse:272, movewindow"
        #   "$mod, mouse:273, resizewindow"
        #   "$mod ALT, mouse:272, resizewindow"
        # ];
      };
    };

    # Optional, hint Electron apps to use Wayland:
    # home.sessionVariables.NIXOS_OZONE_WL = "1";

    programs.firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };
  };
}
