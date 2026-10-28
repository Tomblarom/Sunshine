#!/usr/bin/env bash
# Install a checksum-verified custom AppImage into an existing Sunshine user service.
set -Eeuo pipefail
umask 077

if (( $# < 2 || $# > 3 )); then
  echo "Usage: $0 APPIMAGE SHA256 [EXISTING_SUNSHINE_CONF]" >&2
  exit 2
fi
image=$(realpath -- "$1")
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -x $scripts/verify.sh ]] || { echo 'Keep verify.sh alongside install.sh and executable.' >&2; exit 2; }
digest=${2,,}
config=$(realpath -e -- "${3:-${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf}")
[[ $digest =~ ^[0-9a-f]{64}$ && -f $image && -f $config ]] || exit 2
[[ $(uname -m) == x86_64 ]] || { echo 'This package requires x86_64.' >&2; exit 1; }
root=${SUNSHINE_CUSTOM_ROOT:-$HOME/.local/opt/sunshine-custom}
service=app-dev.lizardbyte.app.Sunshine.service
dropdir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service.d
dropin=$dropdir/99-sunshine-custom.conf
[[ $root = /* && $config = /* ]] || exit 2
# Restrict service paths to characters with unambiguous systemd quoting semantics.
[[ $root != *[$'\n\r%\\\"']* && $config != *[$'\n\r%\\\"']* ]] || exit 2
mkdir -p "$root/releases" "$root/backups"
exec 9>"$root/install.lock"
flock -n 9 || { echo 'Another install or rollback is running.' >&2; exit 1; }
printf '%s  %s\n' "$digest" "$image" | sha256sum -c -
systemctl --user cat "$service" >/dev/null
systemctl --user is-active --quiet "$service" || { echo 'The existing service must be running before installation.' >&2; exit 1; }
if [[ ! -e /dev/fuse ]]; then
  echo 'FUSE is unavailable. Enable /dev/fuse and install libfuse2t64 before installing.' >&2
  exit 1
fi
ldconfig -p | awk '/libfuse.so.2 / {found=1} END {exit !found}' || { echo 'Install libfuse2t64 first.' >&2; exit 1; }
release=$root/releases/$digest.AppImage
stage=$(mktemp "$root/releases/.stage.XXXXXX")
checkdir=$(mktemp -d "$root/.version.XXXXXX")
trap 'rm -f -- "$stage"; rm -rf -- "$checkdir"' EXIT
install -m 700 -- "$image" "$stage"
printf '%s  %s\n' "$digest" "$stage" | sha256sum -c -
timeout 30 "$stage" "$checkdir/version.conf" "log_path=$checkdir/version.log" --version >"$root/version-check.txt" 2>&1
grep -Eqi 'custom|ramfallback' "$root/version-check.txt" || { echo 'The binary does not identify itself as custom.' >&2; exit 1; }
mv -f -- "$stage" "$release"
backup=$(mktemp -d "$root/backups/install-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
systemctl --user cat "$service" >"$backup/service.txt"
systemctl --user show "$service" -p FragmentPath -p DropInPaths -p ExecStart >"$backup/service-state.txt"
configdir=$(dirname -- "$config")
tar -C "$configdir" -cpf "$backup/configuration.tar" .
if [[ -d $dropdir ]]; then
  cp -a -- "$dropdir" "$backup/drop-ins"
fi
if [[ -e $dropin || -L $dropin ]]; then
  cp -a -- "$dropin" "$backup/previous-custom.conf"
fi
if [[ -L $root/current.AppImage ]]; then
  readlink "$root/current.AppImage" >"$backup/previous-image"
fi
printf '%s\n' "$release" >"$backup/installed-image"
printf '%s\n' "$config" >"$backup/config-path"
mkdir -p "$dropdir"
rollback_on_failure() {
  trap - ERR
  echo "Installation failed; restoring previous service override ($backup)." >&2
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
  systemctl --user restart "$service" || true
  exit 1
}
trap rollback_on_failure ERR
ln -sfn -- "$release" "$root/current.AppImage"
printf '[Service]\nExecStart=\nExecStart="%s" "%s" pipewire_use_dmabuf=disabled\n' \
  "$root/current.AppImage" "$config" >"$dropin.tmp"
mv -f -- "$dropin.tmp" "$dropin"
printf '%s\n' "$backup" >"$root/last-backup"
systemctl --user daemon-reload
systemctl --user restart "$service"
sleep 5
systemctl --user is-active --quiet "$service"
SUNSHINE_CUSTOM_ROOT=$root "$scripts/verify.sh"
trap - ERR
printf 'Installed: %s\nBackup: %s\n' "$release" "$backup"
echo 'Run verify.sh, then test a real Moonlight session. Service health alone does not verify capture.'
