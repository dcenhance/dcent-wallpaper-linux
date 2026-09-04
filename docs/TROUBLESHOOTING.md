# Troubleshooting

## DcentWallpapers is missing from Wallpaper settings

Confirm the package is installed:

```bash
kpackagetool6 --type Plasma/Wallpaper --show org.dcentwallpapers.plasma
```

Reinstall and restart Plasma:

```bash
kpackagetool6 --type Plasma/Wallpaper --upgrade ./plasma-plugin
systemctl --user restart plasma-plasmashell.service
```

## Native helper/module not found

The runtime QML import is:

```text
com.github.captsilver.wallpaperEngineKde 1.2
```

Check the module:

```bash
qmlplugindump-qt6 com.github.captsilver.wallpaperEngineKde 1.2 >/dev/null
```

On Fedora/Nobara, files normally live at:

```text
/usr/lib64/qt6/qml/com/github/captsilver/wallpaperEngineKde/
```

If the import fails, rebuild the native module using [INSTALLATION.md](INSTALLATION.md), then restart Plasma.

## Library is empty

Check the configured directories:

```text
/data/SteamLibrary
/data/SteamLibrary/steamapps/workshop/content/431960
```

Each installed item should have its own numeric directory and usually a `project.json`. Dcent does not open Steam automatically and unauthenticated public APIs cannot install every Workshop item.

## Apply works only once or targets the wrong screen

Install the current package build. It caches KDE's output name instead of retaining the transient `QScreen` object and uses KDE's KCM Apply fallback when exact output identity is unavailable.

Inspect containment state:

```bash
kreadconfig6 \
  --file plasma-org.kde.plasma.desktop-appletsrc \
  --group Containments
```

For detailed diagnosis, inspect the full file without editing it while Plasma is running.

## A scene does not load

Run isolated preflight manually:

```bash
./plasma-plugin/contents/tools/dcent-scene-preflight \
  /path/to/workshop/item/scene.json \
  /path/to/wallpaper_engine/assets
```

Exit `0` means the helper completed without a native crash. A non-zero exit, timeout, or signal means Dcent should retain the current wallpaper or use a validated cache.

Do not bypass preflight by manually writing an unverified scene into Plasma configuration.

## Wallpaper is static

- Confirm the item is a scene or animated web/video project rather than a still image.
- Confirm isolated preflight passes.
- Check that FPS is above zero and the wallpaper is not paused by fullscreen/power policy.
- Some Wallpaper Engine scenes use only subtle motion.

Live logs:

```bash
journalctl --user -u plasma-plasmashell.service -f
```

Useful scene messages include `isolated scene preflight passed`, `loading scene`, `receive external texture`, and changing particle/effect diagnostics.

## Audio responsiveness does not work

1. Enable **System audio reactivity**.
2. Play audio through the current default output.
3. Confirm PipeWire/PulseAudio exposes a monitor:

   ```bash
   pactl get-default-sink
   pactl list short sources
   ```

4. Check the Plasma journal for `AudioCapture: active on monitor` and `Audio spectrum`.

A wallpaper must itself implement audio-reactive effects or `wallpaperRegisterAudioListener`; enabling capture cannot make a non-audio wallpaper reactive.

## Clicks do not reach the wallpaper

Enable **Interactive wallpaper mode**. Click forwarding is intentionally disabled otherwise so normal desktop behavior remains available.

Some projects only react in specific regions, require hover before click, or use controls that appear after a delay.

## Wallpaper briefly goes blank while switching

Install the latest runtime and verify all visual backends emit `sig_backendFirstFrame`. The previous backend should remain alive until that signal or the bounded timeout.

If flicker remains, capture the journal around one switch and identify which backend never reports a first frame.

## Plasma crashes or restarts

Check service state and recent logs:

```bash
systemctl --user status plasma-plasmashell.service
journalctl --user -u plasma-plasmashell.service --since "10 minutes ago" --no-pager
```

If one scene is involved, do not reapply it repeatedly. Run it only through the isolated helper. A native renderer or graphics-driver failure after successful preflight can still affect an in-process Plasma backend.

## Excessive GPU or memory use

- Lower FPS from 60 to 30.
- Prefer mirror mode over an extremely wide spanned canvas.
- Disable unnecessary scene effects in Wallpaper settings.
- Use a cached video fallback for very large or problematic scenes.
- Confirm only one Plasma wallpaper renderer is active; normal operation should not leave `linux-wallpaperengine` running.

## Collecting useful diagnostics

Include:

- KDE Plasma and Qt versions
- GPU and driver
- Output names, resolutions, refresh rates, and scaling
- Workshop ID
- Scene/web/video type
- Preflight exit status
- Recent Plasma journal lines
- Whether the problem occurs on one screen, all screens, mirror mode, or span mode

Never include Steam credentials, API keys, browser profiles, SSH keys, or unrelated private configuration.
