#!/usr/bin/env nix-shell
#!nix-shell -i bash -p crowdsec coreutils

# shellcheck shell=bash

wait_for_lapi() {
  while ! nice -n19 cscli lapi status; do
    echo "Waiting for CrowdSec daemon to be ready"
    sleep 0.1
  done
}

add_machine_cscli() {
  if [ "$#" -ne 2 ]; then
    echo "usage: $0 <machinename> <passwordfile>" >&2
    exit 1
  fi

  machinename="$1"
  passwordfile="$2"

  # This command activates a self-service registered sensor
  # And also acts as a status check
  if cscli machines validate "$machinename" >/dev/null; then
    echo "Machine '$machinename' exists with valid data, skipping add"
    return 0
  fi

  if [ ! -r "$passwordfile" ]; then
    echo "error: password file '$passwordfile' not readable" >&2
    exit 2
  fi

  # The idiocy of this tool to not accept a file with a password is unbelievable.
  # The fuckery I need to do to workaround is just stupid.

  exec 3> >(cat >/dev/null)

  # TODO; Fix the password leak in process list
  password=$(cat "$passwordfile")
  if ! cscli machines add "$machinename" --password "$password" --force --file - >&3; then
    exec 3>&-
    echo "failed to add machine '$machinename'" >&2
    exit 1
  fi

  exec 3>&-
  echo "Machine '$machinename' added succesfully"
}

add_bouncer_cscli() {
  if [ "$#" -ne 2 ]; then
    echo "usage: $0 <machinename> <passwordfile>" >&2
    exit 1
  fi

  machinename="$1"
  passwordfile="$2"

  if cscli bouncers inspect "$machinename" >/dev/null; then
    echo "Bouncer '$machinename' exists with valid data, skipping add"
    return 0
  fi

  if [ ! -r "$passwordfile" ]; then
    echo "error: password file '$passwordfile' not readable" >&2
    exit 2
  fi

  # The idiocy of this tool to not accept a file with a password is unbelievable.
  # The fuckery I need to do to workaround is just stupid.

  # TODO; Fix the password leak in process list
  password=$(cat "$passwordfile")
  if ! cscli bouncers add "$machinename" --key "$password" >/dev/null; then
    echo "failed to add bouncer '$machinename'" >&2
    exit 1
  fi

  echo "Bouncer '$machinename' added succesfully"
}
