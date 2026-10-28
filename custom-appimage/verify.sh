#!/usr/bin/env bash
# Verify installed bytes and service process without printing configuration or keys.
set -Eeuo pipefail
root=${SUNSHINE_CUSTOM_ROOT:-$HOME/.local/opt/sunshine-custom}
service=app-dev.lizardbyte.app.Sunshine.service
image=$(readlink -e -- "$root/current.AppImage")
digest=$(basename -- "$image" .AppImage)
[[ $digest =~ ^[0-9a-f]{64}$ ]] || exit 1
printf '%s  %s\n' "$digest" "$image" | sha256sum -c -
checkdir=$(mktemp -d)
trap 'rm -rf -- "$checkdir"' EXIT
expected_version=$(timeout 30 "$image" "$checkdir/version.conf" "log_path=$checkdir/version.log" --version 2>&1)
printf '%s\n' "$expected_version"
grep -Eqi 'custom|ramfallback' <<<"$expected_version"
systemctl --user is-active --quiet "$service"
systemctl --user show "$service" -p ExecStart --value | grep -F -- "$root/current.AppImage" >/dev/null
group=$(systemctl --user show "$service" -p ControlGroup --value)
[[ $group == /* && $group != *..* && -r /sys/fs/cgroup$group/cgroup.procs ]]
count=0
while read -r pid; do
  executable=$(readlink "/proc/$pid/exe" || true)
  if [[ ${executable##*/} == sunshine ]]; then
    actual_version=$(timeout 15 "/proc/$pid/exe" "$checkdir/version.conf" "log_path=$checkdir/version.log" --version 2>&1)
    grep -Eqi 'custom|ramfallback' <<<"$actual_version"
    # Compare the version line, excluding timestamped logging prefixes.
    expected_line=$(grep -Eo 'Sunshine version: .*|[0-9]{4}\.[0-9]+\.[0-9]+[^[:space:]]*' <<<"$expected_version" | tail -1)
    actual_line=$(grep -Eo 'Sunshine version: .*|[0-9]{4}\.[0-9]+\.[0-9]+[^[:space:]]*' <<<"$actual_version" | tail -1)
    [[ -n $expected_line && $actual_line == "$expected_line" ]]
    printf 'Running binary: %s\n' "$actual_line"
    count=$((count + 1))
  fi
done <"/sys/fs/cgroup$group/cgroup.procs"
[[ $count == 1 ]] || { echo "Expected one running Sunshine binary in the service, found $count." >&2; exit 1; }
echo 'User service is active and contains exactly one Sunshine process.'
echo 'Confirm in local logs: custom version, [pipewire] using memory buffers, H.264/HEVC VA-API detection.'
echo 'In Moonlight test video/audio/input, disconnect/reconnect, then record FPS and processing latency with moving content.'
echo 'No live capture or 4K60 result is implied by these checks.'
