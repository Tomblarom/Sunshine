#!/usr/bin/env bash
# Restore only the installer-owned override, preserving current pairing/configuration data.
set -Eeuo pipefail
umask 077
root=${SUNSHINE_CUSTOM_ROOT:-$HOME/.local/opt/sunshine-custom}
service=app-dev.lizardbyte.app.Sunshine.service
dropin=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service.d/99-sunshine-custom.conf
exec 9>"$root/install.lock"
flock -n 9 || { echo 'Another install or rollback is running.' >&2; exit 1; }
backup=${1:-$(cat "$root/last-backup")}
backup=$(realpath -e -- "$backup")
[[ $backup == "$root"/backups/* && -f $backup/installed-image ]] || { echo 'Invalid backup directory.' >&2; exit 2; }
if [[ -f $backup/previous-custom.conf ]]; then
  cp -a -- "$backup/previous-custom.conf" "$dropin"
else
  rm -f -- "$dropin"
fi
if [[ -f $backup/previous-image ]]; then
  ln -sfn -- "$(cat "$backup/previous-image")" "$root/current.AppImage"
else
  rm -f -- "$root/current.AppImage"
fi
systemctl --user daemon-reload
systemctl --user restart "$service"
sleep 5
systemctl --user is-active --quiet "$service"
echo "Restored the service override from $backup. Configuration and old source builds were preserved."
