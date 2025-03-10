#!/usr/bin/env nix-shell
#!nix-shell -i bash -p gnugrep gnused virtualgl

# shellcheck shell=bash

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset WAYLAND_DISPLAY

# Specify that the window manager should use X11 rather than Wayland.
XDG_SESSION_TYPE=x11
export XDG_SESSION_TYPE

XSESSIONSDIR="${XSESSIONSDIR:-}"
if [ "$XSESSIONSDIR" = "" ]; then
	echo "xstartup: No sessions directory set"
	exit 1
fi

SESSIONS="$(echo "$TVNC_WM" | sed -r 's/^.*\/|-session$//g')"
unset TVNC_WM

for SESSION in $SESSIONS; do
	echo "xstartup: Attempting desktop file $XSESSIONSDIR/$SESSION.desktop"
done
for SESSION in $SESSIONS; do
	if [ "$XSESSIONSDIR" != "" ] && [ -f "$XSESSIONSDIR"/"$SESSION".desktop ]; then
		DESKTOP_SESSION="$SESSION"
		export DESKTOP_SESSION
	fi
done
unset SESSIONS

if [ "$DESKTOP_SESSION" = "" ]; then
	echo "xstartup: No matching desktop file found!"
	exit 1
fi

XDG_SESSION_DESKTOP=$DESKTOP_SESSION
export XDG_SESSION_DESKTOP
echo "xstartup: Using '$DESKTOP_SESSION' window manager in"
echo "xstartup:     $XSESSIONSDIR/$DESKTOP_SESSION.desktop"

# Parse the session desktop file to determine the window manager's startup
# command, and set the TVNC_WM environment variable accordingly.
if grep -qE "^Exec\s*=" "$XSESSIONSDIR"/"$DESKTOP_SESSION".desktop; then
	TVNC_WM=$(grep -E "^Exec\s*=" "$XSESSIONSDIR"/"$DESKTOP_SESSION".desktop | sed -r 's/^[^=]+=[[:space:]]*//g')
fi

# Parse the session desktop file to determine the window manager's desktop
# name.
for KEY in DesktopNames X-LightDM-DesktopName; do
	if grep -qE "^$KEY\s*=" "$XSESSIONSDIR"/"$DESKTOP_SESSION".desktop; then
		XDG_CURRENT_DESKTOP=$(grep -E "^$KEY\s*=" "$XSESSIONSDIR"/"$DESKTOP_SESSION".desktop | sed -r 's/(^[^=]+=[[:space:]]*|;$)//g' | sed -r 's/;/:/g')
		export XDG_CURRENT_DESKTOP
	fi
done

TVNC_VGLRUN="${TVNC_VGLRUN:-}"
if [ "${TVNC_VGL:-}" = "1" ]; then
	if [ -z "$TVNC_VGLRUN" ]; then
		TVNC_VGLRUN="vglrun +wm"
	fi
fi

if [ "$TVNC_WM" != "" ]; then
	echo "xstartup: Executing $TVNC_VGLRUN $TVNC_WM"
	exec $TVNC_VGLRUN "$TVNC_WM"
else
	echo "xstartup: No window manager specified or found."
	exit 1
fi
