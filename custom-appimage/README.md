# Custom Sunshine AppImage

This is a third-party build based on the stable Sunshine release v2026.914.233613,
with an explicit PipeWire memory-buffer option and a backport of upstream's
matched-system-libva fix. It is not an official LizardByte release. Consult the
release's provenance and SHA256SUMS for the exact source and build commit.

The stable base includes the fix for
[GHSA-fp6g-27w5-489j](https://github.com/LizardByte/Sunshine/security/advisories/GHSA-fp6g-27w5-489j).
The memory option bypasses the failed DMA-BUF import; it does not repair the
driver's import or promise 4K60 performance. DMA-BUF remains the default when
Sunshine is started without the installer override.

## Runtime requirements

Use Debian 13 x86_64 and an existing working Sunshine user service and
configuration. No sources or compiler are required. Install runtime packages
with the system package manager if missing:

```sh
sudo apt install libfuse2t64 libva2 libva-drm2 libva-x11-2 libdrm2 \
  mesa-va-drivers libegl1 libgl1 libgbm1 libpipewire-0.3-0 libpulse0
```

The host's libva core and backends must come from the same installation; keep
Debian's Mesa VA driver and libdrm updated together. Do not put alternate libva
libraries in LD_LIBRARY_PATH. FUSE requires a usable `/dev/fuse`. The package
does not bundle libva or the GPU driver. CUDA is disabled at build time.

Run inside the existing KDE Wayland user session, with access to its session bus,
Wayland socket, PipeWire and the AMD render node. Existing working input/udev
permissions remain necessary. KWin and portal capture are enabled; AppImage
does not support KMS capture. Do not grant CAP_SYS_ADMIN to this AppImage.

## Install and update

Download the AppImage, SHA256SUMS and these scripts from the same custom release.
Verify the published checksum against the trusted release page. Run as the
desktop user that owns the existing Sunshine service, never through `sudo`:

```sh
chmod +x install.sh rollback.sh verify.sh
./install.sh ./Sunshine_VERSION_x86_64.AppImage PUBLISHED_SHA256 \
  "$HOME/.config/sunshine/sunshine.conf"
./verify.sh
```

Replace the filename and digest with the actual values from this release.
For updates, repeat `install.sh` with the new AppImage and its new digest.

The installer first verifies bytes and custom version, then makes a private
backup of the configuration directory and all current user-service overrides.
It installs under `~/.local/opt/sunshine-custom/`, adds only
`99-sunshine-custom.conf`, and restarts only
`app-dev.lizardbyte.app.Sunshine.service`. This late drop-in supersedes earlier
ExecStart overrides while retaining their files for rollback. It explicitly
passes the existing configuration path and the memory-buffer option on the
command line. It does not edit the main configuration, clients, certificates
or keys. The old executable and source directory remain untouched.

An unsuccessful service/version verification restores the previous override
automatically. Backups contain private credentials: keep them local and do not
upload them with bug reports. Disk backups are not publicly distributed.

Do not run the AppImage's `--install` or `--remove` options: those change shared
udev rules and service files. Do not start a second Sunshine instance manually.

## Verify actual capture

`verify.sh` checks the installed checksum, expected custom version, active user
service and its running Sunshine process. It does not establish GPU capture
success. Check local logs for `using memory buffers` and H.264/HEVC VA-API encoder
detection, then use an already paired Moonlight client:

1. Start moving desktop or game content at 1080p60 using H.264, then HEVC.
2. Disconnect and reconnect twice; test display switching only if a second
   display is already configured.
3. Repeat at 3840x2160/60 with HEVC. Record actual delivered FPS, host processing
   latency and frame/network drops. A static desktop is not a throughput test.

Expected: visible video with VA-API encoding and no repeated RGB DMA-BUF import
errors. RAM copies can add latency; actual 60 FPS requires measurement.

## Rollback

```sh
./rollback.sh
```

This restores the installer-owned override to its pre-install state, restores
the previous AppImage symlink if one existed, and restarts only Sunshine. Other
drop-ins and current configuration remain unchanged. To select an older
installation backup explicitly, pass its full directory path from
`~/.local/opt/sunshine-custom/backups/` to `rollback.sh`.

After rollback, verify service health and a real Moonlight session again. The
configuration archive is an emergency backup, not automatically restored over
new settings or pairings. Keep the previous working source build until both
AppImage streaming and a real rollback have been confirmed.
