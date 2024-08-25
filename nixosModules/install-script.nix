{ lib, pkgs, flake-inputs, config, ... }:
let
  cfg = config.proesmans.installer;
in
{
  options.proesmans.installer = {
    enable = lib.mkEnableOption "Installer script" // {
      description = ''
        Configures a script that performs a full system install.
      '';
    };

    host-attribute = lib.mkOption {
      description = "The hostname to install";
      type = lib.types.str;
      example = "development";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      let
        system = config.nixpkgs.hostPlatform.system;
        guest = pkgs.writeShellApplication {
          name = "guest-deployment";
          runtimeInputs = [ ];
          text = ''
            # File should be sourced!

            # Check if the log file path is provided as an argument
            if [ -z "$1" ]; then
                echo "Usage: source $0 /path/to/logfile"
                return 1
            fi

            LOGFILE="$1"

            # Function to log each command before execution
            log_command() {
                echo "$(date '+%Y-%m-%d %H:%M:%S') $(history 1)" >> "$LOGFILE"
            }

            # Set PROMPT_COMMAND to run log_command before each prompt
            PROMPT_COMMAND=log_command
          '';
        };

        monitor = pkgs.writeShellApplication {
          name = "monitor-deployment";
          runtimeInputs = [ pkgs.expect ];
          text = ''
            # Check if the log file path is provided as an argument
            if [ -z "$1" ]; then
                echo "Usage: $0 /path/to/logfile"
                exit 1
            fi

            LOGFILE="$1"

            expect <<EOF
            # Display an initial message to the user
            send_user "Please run the 'nix develop' command in the other pane to proceed.\n"
            
            # Monitor the log file for changes
            set timeout -1
            spawn tail -f "$LOGFILE"

            expect {
                -re {nix develop.*} {
                    # When a command starting with 'nix develop' is detected
                    send_user "\n[Monitor] Detected 'nix develop' command.\n"
                    
                    # Example action: display a message or run another script
                    # exec /path/to/another_script.sh
                    
                    exp_continue
                }
            }
            EOF
          '';
        };

        setup-invoker = pkgs.writeShellApplication {
          name = "install-host";
          runtimeInputs = [ pkgs.screen ];
          text = ''
            # Create a temporary log file in /tmp
            LOGFILE=$(mktemp /tmp/user_command.XXXXXX.log)

            # Start a new detached screen session
            screen -S monitoringSession -d -m

            # Create a vertical split
            screen -S monitoringSession -X split -v

            # Start the expect monitoring script in the second pane (pane 1)
            screen -S monitoringSession -p 1 -X stuff "${lib.getExe monitor} '$LOGFILE'\n"

            # Go back to the first pane (pane 0) and source the user logging script
            screen -S monitoringSession -p 0 -X focus
            screen -S monitoringSession -p 0 -X stuff "source ${lib.getExe guest} '$LOGFILE'\n"

            # Attach to the screen session so the user can see both panes
            screen -r monitoringSession
          '';
        };
      in
      [ setup-invoker ];
  };
}
