# shellcheck shell=sh disable=SC1091
# Adapted from https://github.com/ublue-os/toolboxes/blob/main/toolboxes/bluefin-cli/files/etc/profile.d/00-bluefin-cli-brew-firstrun.sh
if test "$(id -u)" -gt "0"; then
  blue=$(printf '\033[38;5;32m')
  bold=$(printf '\033[1m')
  normal=$(printf '\033[0m')

  if test ! -d /usr/local/share/bash-completion/completions; then
    printf "Setting up Tab-Completions...\t\t\t "
    sudo mkdir -p /usr/local/share/bash-completion
    sudo mount --bind /run/host/usr/share/bash-completion /usr/local/share/bash-completion
    if test -x /run/host/usr/bin/ujust; then
      sudo ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/ujust
    fi
    printf "%s[ OK ]%s\n" "${blue}" "${normal}"
  fi

  if test -d /nix/; then
    printf "Setting up nix...\t\t\t "
    sudo usermod -a -G nix-users "${USER}"
  fi

  if test ! -f /etc/cli.firstrun; then
    sudo touch /etc/cli.firstrun
    printf "\ncli first run complete.\n\n"
  fi

fi
