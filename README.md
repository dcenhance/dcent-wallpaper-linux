<div align="center">
  <img src=".github/assets/banner.svg" alt="DcentWallpapers — Wallpaper Engine projects, native to KDE Plasma" width="100%">

  <br>

  [![CI](https://github.com/dcenhance/dcent-wallpaper-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/dcenhance/dcent-wallpaper-linux/actions/workflows/ci.yml)
  [![Pages](https://github.com/dcenhance/dcent-wallpaper-linux/actions/workflows/pages.yml/badge.svg)](https://dcenhance.github.io/dcent-wallpaper-linux/)
  [![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-1d99f3?logo=kde&logoColor=white)](https://kde.org/plasma-desktop/)
  [![Wayland](https://img.shields.io/badge/Wayland-ready-ffbc00)](https://wayland.freedesktop.org/)
  [![License: GPL-2.0-only](https://img.shields.io/badge/license-GPL--2.0--only-35c46a.svg)](LICENSE)

  **Run local Wallpaper Engine projects as real KDE Plasma wallpapers—without covering the desktop with an overlay window.**

  [Website](https://dcenhance.github.io/dcent-wallpaper-linux/) · [Install](docs/INSTALLATION.md) · [User guide](docs/USER_GUIDE.md) · [Architecture](docs/ARCHITECTURE.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)
</div>

---

## Why DcentWallpapers?

DcentWallpapers is a `Plasma/Wallpaper` provider, not a desktop-sized application window. Plasma owns the wallpaper item, its screen placement, its lifecycle, and its relationship with desktop input.

| Capability | Implementation |
|---|---|
| **Live scenes** | Maintained CaptSilver `SceneViewer`, gated by isolated native preflight |
| **Audio response** | Shared PipeWire/PulseAudio capture with 64 left + 64 right FFT bands |
| **Web projects** | Qt WebEngine with Wallpaper Engine properties, directories, audio, and clickable controls |
| **Video and images** | Native Qt Multimedia, MPV, animated-image, and static-image paths |
| **Multiple displays** | Exact KDE output targeting, mirroring, and one synchronized spanned canvas |
| **Safe switching** | Current backend remains visible until its replacement produces a valid first frame |
| **Project settings** | Per-wallpaper properties, presets, conditions, colors, sliders, files, and bundled assets |

## Safety first

```text
Workshop project
       │
       ▼
process-isolated preflight
       │
       ├── valid first frame ──► live SceneViewer inside Plasma
       │
       └── crash / timeout ────► validated cached video or still
                                      │
                                      └── no safe result: keep current wallpaper
```

Preview thumbnails are gallery metadata only. They never become runtime sources. Async results are tied to an immutable selection generation so stale work cannot apply a previously selected wallpaper.

> [!IMPORTANT]
> Native scenes run in-process only after isolated preflight. This substantially reduces parser/startup risk, but no in-process native renderer can guarantee immunity from a later driver or renderer fault. The exact boundary is documented in [Architecture and safety](docs/ARCHITECTURE.md).

## Supported content

- Wallpaper Engine scenes and presets
- Web wallpapers using Wallpaper Engine property and audio APIs
- Video wallpapers
- Static and animated images
- File and directory properties with project-local asset discovery
- Clickable and draggable wallpaper controls
- Audio-reactive effects and scripts
- Per-output, mirrored, and spanned layouts

## Requirements

- KDE Plasma 6 on Wayland or X11
- Qt 6 with Qt WebEngine
- Python 3
- PipeWire with PulseAudio compatibility for system-audio reactivity
- A local Wallpaper Engine library
- The maintained CaptSilver Wallpaper Engine KDE native QML module

Tested primarily on Fedora/Nobara KDE with NVIDIA graphics. See the [platform support matrix](docs/PLATFORM_SUPPORT.md) before installing on another desktop or distribution.

## Install

Build the native CaptSilver module and isolated helper first. The exact packages and secure build adjustment are in [docs/INSTALLATION.md](docs/INSTALLATION.md).

```bash
git clone https://github.com/dcenhance/dcent-wallpaper-linux.git
cd dcent-wallpaper-linux

kpackagetool6 --type Plasma/Wallpaper --install ./plasma-plugin
systemctl --user restart plasma-plasmashell.service
```

For an existing installation, use `--upgrade` instead of `--install`.

Then open **System Settings → Wallpaper**, choose **DcentWallpapers**, and set your Steam library path.

Default layout:

```text
/data/SteamLibrary/
├── steamapps/common/wallpaper_engine/assets/
└── steamapps/workshop/content/431960/<WorkshopId>/
```

## Configure once, keep project settings separate

The plugin uses one compact **Configure** page:

- **Wallpaper settings** are declared by and persisted for the selected project.
- **DcentWallpapers settings** control FPS, scaling, audio capture, interaction, and multi-screen behavior.

Single-click selects. Double-click selects and applies that exact card. Apply remains repeatable after KDE replaces or invalidates its temporary `QScreen` object.

## Development

```bash
uv run --with pytest pytest -q \
  tests/test_multiscreen.py \
  tests/test_properties.py \
  tests/test_workshop.py
```

```bash
QML_XHR_ALLOW_FILE_READ=1 \
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
/usr/lib64/qt6/bin/qmltestrunner -input "$PWD/tests/qml" -o -,txt
```

Verified baseline for this release:

```text
Python   52 passed
QML      64 passed
Native audio monitor smoke test   3 passed
QML lint exit                     0
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before proposing runtime changes.

## Documentation

| Guide | Covers |
|---|---|
| [Installation](docs/INSTALLATION.md) | Dependencies, CaptSilver build, helper build, package installation |
| [User guide](docs/USER_GUIDE.md) | Apply, settings, assets, input, screens, audio, and fallbacks |
| [Architecture](docs/ARCHITECTURE.md) | Ownership, routing, first-frame handoff, preflight, and security |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Import, scene, audio, GPU, input, and Plasma diagnostics |
| [Platform support](docs/PLATFORM_SUPPORT.md) | Supported desktops, sessions, GPUs, and known boundaries |
| [Security policy](SECURITY.md) | Vulnerability reporting and native-scene boundaries |
| [Changelog](CHANGELOG.md) | User-visible additions and fixes |

## Project principles

- Plasma owns the wallpaper.
- No persistent floating or layer-shell renderer.
- Never promote a preview into a runtime source.
- Never load an unverified scene parser input in Plasma.
- Keep the current wallpaper until its replacement is ready.
- Keep Wallpaper Engine properties separate from provider settings.
- Treat local libraries and user configuration as private data.

## License and upstream work

Distributed under [GPL-2.0-only](LICENSE), matching the upstream Wallpaper Engine KDE plugin. See [Acknowledgements and provenance](ACKNOWLEDGEMENTS.md) for the original catsout project, the maintained CaptSilver renderer, and Dcent's modifications.
