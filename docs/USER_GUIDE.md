# User guide

## Opening DcentWallpapers

1. Right-click the desktop and choose **Desktop and Wallpaper** or open **System Settings → Wallpaper**.
2. Choose **DcentWallpapers** as the wallpaper type.
3. The Configure page displays the local library and selected wallpaper settings.

## Selecting and applying

- **Single-click** selects a wallpaper and opens its details.
- **Double-click** selects and applies that exact wallpaper.
- **Apply** can be used repeatedly; it is not a one-shot action.
- Keyboard/accessibility activation follows the same selection-owned Apply path.

An expensive scene preparation is never started by ordinary single-click selection. Scene work begins only after deliberate Apply or double-click activation.

## Configure page

### Wallpaper settings

This section is generated from the selected project's `project.json` and is stored per Workshop ID. Supported controls include:

- Boolean toggles
- Sliders and numeric values
- Colors
- Text
- Combo-box choices
- File and directory assets
- Presets and conditions

If a wallpaper bundles multiple backgrounds, overlays, videos, or scene textures, DcentWallpapers lists compatible assets from that wallpaper's own directory. Workshop preview thumbnails are never treated as runtime assets.

### DcentWallpapers settings

General controls include:

- **Multiple screens**: span one canvas or mirror the complete wallpaper
- **Background scaling**: fill, fit, or stretch
- **FPS**: native scene rendering rate
- **Volume / Mute audio**: wallpaper-owned audio
- **System audio reactivity**: lets compatible scenes and web projects react to PipeWire output
- **Interactive wallpaper mode**: forwards desktop pointer input to compatible wallpapers

Wallpaper Engine project properties remain separate from these general provider controls.

## Multi-screen behavior

- **One wallpaper across all screens** renders a shared virtual canvas and gives each output its portion.
- **Same wallpaper on every screen** renders the complete wallpaper independently on each screen.
- When KDE's **Set for all screens** mode is active, the interface does not expose conflicting per-screen wallpaper choices.

Dcent resolves KDE's transient `QScreen` object to a stable output name. If exact screen identity is unavailable, it falls back to KDE's normal KCM Apply lifecycle.

## Clickable wallpapers

Enable **Interactive wallpaper mode** for projects with menus, buttons, drag interactions, or other pointer controls. Dcent forwards left-click, drag, hover, and movement events to the active web or native scene target.

Disable it when normal desktop behavior should take priority.

## Audio-responsive wallpapers

Enable **System audio reactivity**. Dcent uses the monitor of the active PipeWire/PulseAudio output and provides Wallpaper Engine-compatible stereo spectrum data:

```text
64 left-channel bands + 64 right-channel bands = 128 values
```

Muting wallpaper-owned audio does not disable system-audio analysis. These settings control different things:

- **Mute audio** silences sound produced by the wallpaper.
- **System audio reactivity** controls whether the wallpaper may react to other system playback.

A wallpaper only reacts if its own scene scripts, effects, or JavaScript implement audio processing.

## Scene safety and fallbacks

Before Plasma receives a native scene, Dcent starts a disposable preflight helper. The helper must produce a first frame within its timeout.

- Pass: load the live native scene in Plasma.
- Crash, timeout, or parser rejection: query validated cached video/still fallbacks.
- No safe fallback: preserve the current wallpaper rather than use the preview image.

## Switching without flicker

Dcent keeps the active backend visible while the candidate backend starts. It promotes the candidate only after the candidate reports its first valid frame. A five-second timeout prevents a failed candidate from retaining resources indefinitely.

## Login screen

The login-screen option uses only a safe still preview through KDE's built-in login provider. Live scene, web, audio, and interactive processing stay disabled before login.
