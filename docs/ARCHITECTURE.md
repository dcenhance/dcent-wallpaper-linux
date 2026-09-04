# Architecture and safety

## Runtime ownership

`org.dcentwallpapers.plasma` is a `Plasma/Wallpaper` package. Plasma owns the wallpaper item, its lifecycle, screen placement, and input relationship with the desktop. Normal operation does not launch `linux-wallpaperengine` as a floating or layer-shell window.

## Main components

| Component | Responsibility |
|---|---|
| `plasma-plugin/contents/ui/config.qml` | Catalog, selection, settings, scene preparation, and KCM Apply behavior |
| `plasma-plugin/contents/ui/main.qml` | Plasma runtime, backend routing, pause/input behavior, and first-frame handoff |
| `plasma-plugin/contents/pyext.py` | Local catalog, project parsing, Plasma configuration RPC, preflight, and fallback cache operations |
| `plasma-plugin/contents/ui/Pyext.qml` | QML-to-Python JSON-RPC client |
| `backend/Image.qml` | Static image renderer |
| `backend/QtMultimedia.qml` | Video and prepared scene-fallback playback |
| `backend/QtWebView.qml` | Web wallpaper runtime, project properties, directories, input, and native audio bridge |
| `backend/Scene.qml` | CaptSilver `SceneViewer` wrapper for live native scene rendering |
| `dcent-scene-preflight` | Disposable process that validates native scene startup |

## Source ownership

Runtime sources and gallery previews are deliberately separate:

- `PreviewPath` is gallery/login-screen metadata.
- `WallpaperSource` is the packed real runtime source.
- `MediaPath` identifies the playable local source.
- `WallpaperWorkShopId` binds configuration and source ownership to one project.

A preview thumbnail must never populate a runtime source field. Generation IDs prevent a slow result from an older selection from replacing a newer selection.

## Backend routing

```text
selected project
    │
    ├─ image ───────────────► Image.qml
    ├─ video ───────────────► QtMultimedia.qml or Mpv.qml
    ├─ web ─────────────────► QtWebView.qml
    └─ scene
         │
         ├─ isolated preflight passes ─► Scene.qml / SceneViewer
         └─ preflight fails
                │
                ├─ validated cached video ─► QtMultimedia.qml
                ├─ validated cached still ─► Image.qml
                └─ no safe result ─────────► retain current wallpaper
```

Scene preflight runs during deliberate configuration Apply and again in the Plasma runtime. Rechecking at runtime protects startup and config reload paths that do not pass through an open Wallpaper KCM.

## First-frame handoff

Backend switching uses two object slots:

- `item`: the candidate/current active backend
- `retiringItem`: the previous backend retained during startup

A replacement is created without immediately destroying the previous backend. Each backend emits `sig_backendFirstFrame` after usable content exists. The signal destroys the retiring backend. A bounded timeout handles broken backends that never emit.

This prevents an intentional empty-loader frame during changes and reapplication.

## Native scene renderer

Dcent imports CaptSilver's maintained module:

```qml
import com.github.captsilver.wallpaperEngineKde 1.2
```

Important exported types include:

- `SceneViewer`
- `MouseGrabber`
- `TTYSwitchMonitor`
- `WebAudioBridge`

`SceneViewer` runs in-process inside `plasmashell` so Plasma remains the wallpaper owner and can render native scene animation efficiently. It receives the real scene source, Wallpaper Engine assets path, FPS, scaling, mute/volume, speed, per-wallpaper property JSON, and system-audio-capture state.

## Crash isolation boundary

Preflight is a separate native process with core dumps disabled and a bounded timeout. It catches parser/initial-render crashes before the same input reaches `plasmashell`.

Limit: once a scene passes and runs in-process, a later native driver or renderer fault can still affect Plasma. Complete fault isolation would require a persistent out-of-process renderer that shares frames back into a Plasma-owned texture. That architecture is not currently implemented.

## Audio pipeline

CaptSilver owns one shared system-audio capture bus:

```text
PipeWire/PulseAudio monitor
    → stereo PCM at 48 kHz
    → overlapping FFT analysis
    → 64 left + 64 right normalized bands
    ├─ native SceneViewer effects/scripts
    └─ WebAudioBridge → wallpaperRegisterAudioListener()
```

Capture starts when a subscriber enables system-audio reactivity and shuts down when the last subscriber disappears. Monitor rebinding handles output-device changes.

## Web wallpaper compatibility

`QtWebView.qml` provides:

- A reference viewport transform for mixed-DPI multi-screen layouts
- Wallpaper Engine user/general properties
- File and directory property callbacks
- `wallpaperRegisterAudioListener`
- `wallpaperRequestRandomFileForProperty`
- Click and focus forwarding when interactive mode is enabled

The native module is built without the upstream process-wide `--disable-web-security` flag. Dcent enables only the narrower WebEngine capabilities needed by local projects.

## Apply transaction

1. Snapshot the exact selected item and selection generation.
2. Resolve the selected KDE output to a stable name/index.
3. Validate or prepare the real runtime source.
4. Write all explicit configuration keys.
5. Set `org.dcentwallpapers.plasma` as the containment wallpaper provider.
6. Reload the containment.
7. Read the configuration back and verify source, type, Workshop ID, and target.

If KDE replaces its transient `QScreen`, the cached output name is used. If exact identity cannot be recovered safely, the KCM's own Apply path is used instead.

## Security notes

- No credentials are embedded in the package.
- Public Workshop metadata does not authorize authenticated subscriptions.
- Project-local asset discovery stays inside the selected wallpaper roots.
- Preview files are never promoted to runtime sources.
- Unsafe native inputs are blocked before in-process loading.
- Login rendering is still-only.
- The native CaptSilver build used by Dcent removes its upstream process-wide `--disable-web-security` mutation.
