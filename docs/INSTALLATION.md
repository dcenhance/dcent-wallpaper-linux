# Installation

## 1. Install runtime and build dependencies

These package names are for current Fedora/Nobara releases:

```bash
sudo dnf install -y \
  cmake ninja-build gcc-c++ git \
  kf6-kconfig-devel kf6-knotifications-devel kf6-kcrash-devel \
  kf6-ki18n-devel kf6-kcoreaddons-devel kf6-kglobalaccel-devel \
  kf6-kxmlgui-devel plasma-activities-devel \
  qt6-qtwebengine-devel qt6-qtwebchannel-devel \
  pulseaudio-libs-devel libglvnd-devel mesa-libgbm-devel \
  lz4-devel mpv-devel freetype-devel fontconfig-devel
```

Other distributions need equivalent Qt 6, KDE Frameworks 6, Vulkan, PulseAudio/PipeWire, mpv, LZ4, FreeType, Fontconfig, EGL, GL, and GBM development packages.

## 2. Build the maintained CaptSilver module

DcentWallpapers imports:

```qml
import com.github.captsilver.wallpaperEngineKde 1.2
```

Clone and initialize all nested renderer dependencies:

```bash
git clone https://github.com/CaptSilver/wallpaper-engine-kde-plugin.git
cd wallpaper-engine-kde-plugin
git submodule update --init --recursive --depth 1
```

### Security adjustment

The upstream plugin currently appends `--disable-web-security` to `QTWEBENGINE_CHROMIUM_FLAGS` during module initialization. DcentWallpapers does not need this process-wide relaxation. Before building, remove the `QTWEBENGINE_CHROMIUM_FLAGS` block from `src/plugin.cpp`, while retaining:

```cpp
qputenv("QML_XHR_ALLOW_FILE_READ", "1");
```

This keeps local QML reads working without weakening every Qt WebEngine instance inside `plasmashell`.

Configure and build:

```bash
CC=gcc CXX=g++ cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DUSE_PLASMAPKG=ON
cmake --build build --parallel 4
sudo cmake --install build
```

The installed module should be under:

```text
/usr/lib64/qt6/qml/com/github/captsilver/wallpaperEngineKde/
```

The library directory may be `/usr/lib` on non-Fedora distributions.

Confirm that QML can load the module:

```bash
qmlplugindump-qt6 com.github.captsilver.wallpaperEngineKde 1.2 >/dev/null
```

## 3. Build the isolated scene preflight helper

From the DcentWallpapers repository root:

```bash
g++ -std=c++17 -O2 tools/scene_preflight.cpp \
  -o tools/dcent-scene-preflight \
  $(pkg-config --cflags --libs Qt6Gui Qt6Qml Qt6Quick)
install -m 0755 tools/dcent-scene-preflight \
  plasma-plugin/contents/tools/dcent-scene-preflight
```

## 4. Install the Plasma wallpaper package

```bash
kpackagetool6 --type Plasma/Wallpaper --install ./plasma-plugin
systemctl --user restart plasma-plasmashell.service
systemctl --user is-active plasma-plasmashell.service
```

A successful final command prints `active`.
For an existing installation, replace `--install` with `--upgrade`.

## 5. Configure library paths

Open **System Settings → Wallpaper**, select **DcentWallpapers**, then set the Steam library if it differs from `/data/SteamLibrary`.

The expected Workshop layout is:

```text
<SteamLibrary>/steamapps/workshop/content/431960/<WorkshopId>/project.json
```

Wallpaper Engine's shared assets are expected at:

```text
<SteamLibrary>/steamapps/common/wallpaper_engine/assets
```

## Updating

After source changes:

```bash
kpackagetool6 --type Plasma/Wallpaper --upgrade ./plasma-plugin
systemctl --user restart plasma-plasmashell.service
```

Updating the QML package does not rebuild the CaptSilver native module. Rebuild and reinstall it separately when its source changes.
