# Platform support matrix

DcentWallpapers is designed to degrade safely, not to claim identical behavior on every Linux desktop. Support depends on the desktop wallpaper API, Qt WebEngine, GPU driver, audio stack, and the individual Wallpaper Engine project.

| Environment | Status | Notes |
|---|---|---|
| KDE Plasma 6 + Wayland | **Supported / tested** | Primary target. Plasma owns the wallpaper item. |
| KDE Plasma 6 + X11 | **Best effort** | The Plasma provider is compatible; fallback capture is most complete here. |
| Fedora / Nobara KDE | **Supported / tested** | Main development and runtime target. |
| NVIDIA Vulkan | **Supported / tested** | Tested with RTX 4070 Ti. Driver versions can affect native scenes. |
| Mesa AMD/Intel | **Expected** | Requires Vulkan and Qt 6 support; broad hardware testing remains needed. |
| Hyprland | **Not supported by this plugin** | Hyprland has no Plasma wallpaper-containment API. It requires a separate layer-shell backend. |
| GNOME | **Not supported by this plugin** | GNOME does not load Plasma wallpaper packages. |
| Plasma 5 | **Not supported** | This release targets Plasma 6 and Qt 6. |
| Login manager | **Still preview only** | Live scenes, web, audio, and interaction intentionally remain disabled before login. |

## What is portable

- The Python catalog and property logic use the standard library.
- The QML provider uses Qt 6 and KDE Plasma APIs.
- Native scenes require Vulkan, the CaptSilver QML module, and compatible GPU drivers.
- Web wallpapers require Qt WebEngine.
- System-audio response requires PipeWire's PulseAudio compatibility monitor.

## What varies by wallpaper

Wallpaper Engine projects are third-party content. A project may depend on Windows-only APIs, unsupported shaders, missing assets, WebGL behavior, unusual video codecs, or scripts that were never designed for Linux.

DcentWallpapers therefore uses this policy:

1. Validate native scenes in an isolated preflight process.
2. Load only scenes that produce a valid first frame.
3. Use a validated cached fallback for rejected scenes.
4. Preserve the current wallpaper when no safe replacement is available.

## Before reporting a compatibility issue

Record:

- Distribution and kernel
- Plasma and Qt versions
- Wayland or X11
- GPU and driver
- Output count, resolution, scale, and refresh rate
- Wallpaper Engine Workshop ID and type
- Preflight result
- Whether the issue affects native, web, video, or image backends

See [Troubleshooting](TROUBLESHOOTING.md) for diagnostic commands.
