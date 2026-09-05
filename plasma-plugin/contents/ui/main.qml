import QtQuick
import com.github.captsilver.wallpaperEngineKde
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

WallpaperItem {
Rectangle {
    id: background
    anchors.fill: parent
    color: wallpaper.configuration.BackgroundColor

    property string steamlibrary: Qt.resolvedUrl(wallpaper.configuration.SteamLibraryPath).toString()
    property string source: Qt.resolvedUrl(wallpaper.configuration.WallpaperSource).toString()
    property string previewPath: wallpaper.configuration.PreviewPath ? Qt.resolvedUrl(wallpaper.configuration.PreviewPath).toString() : ""
    property int scenePreflightGeneration: 0
    property string multiScreenMode: wallpaper.configuration.MultiScreenMode || "mirror"
    property int virtualDesktopX: wallpaper.configuration.VirtualDesktopX || 0
    property int virtualDesktopY: wallpaper.configuration.VirtualDesktopY || 0
    property int virtualDesktopWidth: wallpaper.configuration.VirtualDesktopWidth || 0
    property int virtualDesktopHeight: wallpaper.configuration.VirtualDesktopHeight || 0
    readonly property bool spanEnabled: multiScreenMode === "span" && virtualDesktopWidth > 0 && virtualDesktopHeight > 0
    readonly property real spanCanvasX: spanEnabled ? -(Screen.virtualX - virtualDesktopX) : 0
    readonly property real spanCanvasY: spanEnabled ? -(Screen.virtualY - virtualDesktopY) : 0
    readonly property real spanCanvasWidth: spanEnabled ? virtualDesktopWidth : width
    readonly property real spanCanvasHeight: spanEnabled ? virtualDesktopHeight : height

    property string filterStr: wallpaper.configuration.FilterStr

    property int    videoBackend: wallpaper.configuration.VideoBackend
    property int    switchTimer: wallpaper.configuration.SwitchTimer
    property int    fps: wallpaper.configuration.Fps
    property string scaling: wallpaper.configuration.Scaling || "fill"
    property bool disableParallax: wallpaper.configuration.DisableParallax
    property bool disableParticles: wallpaper.configuration.DisableParticles
    property bool systemAudioCapture: wallpaper.configuration.SystemAudioCapture
    property int presentMode: 0
    property bool hdrOutput: false
    property string postProcessing: ""

    function parsePropertyOverrides(raw) {
        if (raw && typeof raw === "object" && !Array.isArray(raw))
            return raw
        if (!raw || typeof raw !== "string")
            return ({})
        try {
            const parsed = JSON.parse(raw)
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
        } catch (error) {
            console.error("DcentWallpapers: invalid PropertyOverrides: " + error)
            return ({})
        }
    }
    property var projectPropertyOverrides: parsePropertyOverrides(wallpaper.configuration.PropertyOverrides)
    property string userPropsJson: JSON.stringify(projectPropertyOverrides)
    property string projectPath: wallpaper.configuration.WallpaperPath || ""

    property bool   randomizeWallpaper: wallpaper.configuration.RandomizeWallpaper
    property bool   noRandomWhilePaused: wallpaper.configuration.NoRandomWhilePaused
    property bool   mouseInput: wallpaper.configuration.MouseInput
    property bool   mpvStats: wallpaper.configuration.MpvStats

    property bool   pauseOnBatPower: wallpaper.configuration.PauseOnBatPower
    property int    pauseBatPercent: wallpaper.configuration.PauseBatPercent


    property var curOpt: ({})
    property string workshopid: wallpaper.configuration.WallpaperWorkShopId
    property int optionLoadGeneration: 0
    function refreshWallpaperOptions() {
        const workshopId = workshopid
        const generation = ++optionLoadGeneration
        pyext.read_wallpaper_config(workshopId).then((res) => {
            if (generation !== background.optionLoadGeneration || workshopId !== background.workshopid)
                return
            background.curOpt = res || ({})
        })
    }
    onWorkshopidChanged: refreshWallpaperOptions()
    function get_opt_value(key, def) {
        if(curOpt.hasOwnProperty(key))
            return curOpt[key];
        return def;
    }
    property int    displayMode: get_opt_value('display_mode', wallpaper.configuration.DisplayMode)
    property bool   mute: get_opt_value('mute_audio', wallpaper.configuration.MuteAudio)
    property int    volume: get_opt_value('volume', wallpaper.configuration.Volume)
    property real    speed: get_opt_value('speed', wallpaper.configuration.Speed)
    property int    rotationDeg: get_opt_value('rotation', wallpaper.configuration.Rotation)

    property bool   perOptChanged: wallpaper.configuration.PerOptChanged
    onPerOptChangedChanged: refreshWallpaperOptions()

    // auto pause
    property bool   ok: !windowModel.reqPause && !powerSource.reqPause

    // detect TTY switch and pause wallpaper(s)
    TTYSwitchMonitor {
        id: ttyMonitor
        onTtySwitch: {
            if (sleep) {
                console.log("Preparing for sleep (possibly a VT switch)");
                if (backendLoader.item) backendLoader.item.pause();
            } else {
                console.log("Waking up (VT switch back)");
                if (backendLoader.item) backendLoader.item.play();
            }
        }
    }

    property string nowBackend: ""

    property var mouseHooker
    Component {
        id: mouseHookerComponent
        MouseGrabber {
            objectName: "interactiveWallpaperMouseGrabber"
            z: 1000000
            anchors.fill: parent
            visible: true
            enabled: true
        }
    }
    property bool hasLib: Common.checklib_wallpaper(background)

    property var customConf: Common.loadCustomConf(wallpaper.configuration.CustomConf)

    property string wallpaperPath
    property string wallpaperType

    signal sig_backendFirstFrame(string backname)
    function onBackendFirstFrame(backname) {
        console.error(`backend ${backname} first frame`);
        if (wallpaper.hasOwnProperty('accentColor'))
            wallpaper.accentColorChanged();
    }

    Component.onDestruction: {
        if(mouseHooker) {
            mouseHooker.destroy();
        }
    }

    function applySource() {
        const { path, type } = Common.unpackWallpaperSource(source);
        const path_changed = background.wallpaperPath !== path;
        const type_changed = background.wallpaperType !== type;
        const is_infobackend = background.nowBackend === "InfoShow";

        if(type_changed) wallpaperType = type;
        if(path_changed) wallpaperPath = path;

        if(type_changed || path_changed || is_infobackend || !source) {
            loadBackend();
        }

        sourceCallback();
    }

    function getWorkshopIDPath() {
        return Common.getWorkshopDir(this.steamlibrary) + `/${this.workshopid}`;
    }

    function projectIdFromPath() {
        const normalized = String(projectPath || "").replace(/\/+$/, "");
        const candidate = normalized.substring(normalized.lastIndexOf('/') + 1);
        return /^\d+$/.test(candidate) ? candidate : workshopid;
    }

    onMouseInputChanged: {
        if(this.mouseInput) {
            hookTimer.start();
        }
        else if(this.mouseHooker) {
            this.mouseHooker.target = null;
            this.mouseHooker.destroy();
            this.mouseHooker = null;
        }
    }

    Timer {
        id: hookTimer
        running: true
        repeat: false
        interval: 2000
        property int tryTimes: 0
        onTriggered: {
            tryTimes++;
            if(tryTimes >= 10 || !background.hasLib || !background.mouseInput) return;
            if(background.mouseHooker) return;
            background.hookMouse();
        }
        Component.onCompleted: {
            background.hookMouse.connect(background.hookMouseSlot);
        }
    }
    signal hookMouse
    function hookMouseSlot() {
        if(!background.doHookMouse()) {
            hookTimer.start();
        } else {
            hookTimer.tryTimes = 0;
        }
    }
    function doHookMouse() {
        if(background.Window) {
            let hookParent = null;
            const screenArea = Common.findItem(Window.contentItem, "MouseEventListener");
            if(screenArea !== null)
                hookParent = Common.findItem(screenArea, "QQuickGridView");
            if(hookParent === null)
                hookParent = Common.findItem(Window.contentItem, "AppletsLayout");
            if(hookParent === null)
                hookParent = Common.findItem(Window.contentItem, "FolderViewDropArea");
            if(hookParent === null)
                return false;
            console.error("DcentWallpapers: interactive mouse target " + hookParent);
            if(background.mouseHooker) background.mouseHooker.destroy();
            background.mouseHooker = mouseHookerComponent.createObject(hookParent);
            return true;
       }
       return false;
    }

    WindowModel {
        id: windowModel
        screenGeometry: wallpaper.parent.screenGeometry
        filterByScreen: wallpaper.configuration.PauseFilterByScreen
        modePlay: wallpaper.configuration.PauseMode
        resumeTime: wallpaper.configuration.ResumeTime
    }

    PowerSource {
        id: powerSource
        readonly property bool reqPause: {
            (background.pauseOnBatPower && (st_battery_state == 'NoCharge' || st_battery_state == 'Discharging')) ||
            (background.pauseBatPercent !== 0 && st_battery_has && st_battery_percent < background.pauseBatPercent)
        }
    }

    Pyext {
        id: pyext
    }
    WallpaperListModel {
        id: wpListModel
        enabled: background.randomizeWallpaper
        workshopDirs: Common.getProjectDirs(background.steamlibrary)
        globalConfigPath: Common.getGlobalConfigPath(background.steamlibrary)
        filterStr: background.filterStr
        initItemOp: (item) => {
            if(!background.customConf) return;
            item.favor = background.customConf.favor.has(item.workshopid);
        }
        readfile: pyext.readfile

        function changeWallpaper(index) {
            if(this.model.count === 0 || index < 0 || index >= this.model.count) return;
            const model = this.model.get(index);
            const packedSource = Common.packWallpaperSource(model);
            const unpacked = Common.unpackWallpaperSource(packedSource);
            wallpaper.configuration.WallpaperPath = Common.urlNative(model.path);
            wallpaper.configuration.PreviewPath = Common.urlNative(Common.getWpModelPreviewSource(model));
            wallpaper.configuration.MediaPath = Common.urlNative(unpacked.path);
            wallpaper.configuration.WallpaperType = unpacked.type;
            wallpaper.configuration.PropertyOverrides = "";
            wallpaper.configuration.WallpaperWorkShopId = model.workshopid;
            wallpaper.configuration.WallpaperSource = packedSource;
        }
    }
    Timer {
        id: randomizeTimer
        running: background.randomizeWallpaper
        interval: background.switchTimer * 1000 * 60
        repeat: true
        onTriggered: {
            if(!(background.noRandomWhilePaused && !background.ok)) {
                const i = Math.floor(Math.random() * wpListModel.model.count);
                wpListModel.changeWallpaper(i);
            }
        }
    }

    // lauch pause time to avoid freezing
    Timer {
        id: lauchPauseTimer
        running: false
        repeat: false
        interval: 300
        onTriggered: {
            backendLoader.item.pause();
            playTimer.start();
        }
    }
    Timer{
        id: playTimer
        running: false
        repeat: false
        interval: 5000
        onTriggered: { background.autoPause(); }
    }
    // lauch pause end

    // As always autoplay for refresh lastframe, sourceChange need autoPause
    // need a time for delay, which is needed for refresh
    function sourceCallback() {
        sourcePauseTimer.start();
    }
    Timer {
        id: sourcePauseTimer
        running: false
        repeat: false
        interval: 200
        onTriggered: background.autoPause();
    }
    // main
    Item {
        id: backendLoader
        readonly property bool _swapped: background.rotationDeg === 90 || background.rotationDeg === 270
        width: _swapped ? parent.height : parent.width
        height: _swapped ? parent.width : parent.height
        anchors.centerIn: parent
        rotation: background.rotationDeg
        property var item: null
        property var retiringItem: null

        signal loaded

        Timer {
            id: backendSwapTimeout
            interval: 5000
            repeat: false
            onTriggered: backendLoader.finishBackendSwap()
        }

        Connections {
            target: background
            function onSig_backendFirstFrame(backname) {
                backendLoader.finishBackendSwap()
            }
        }

        Component.onCompleted: {
            if(background.hasLib) {
                this.loaded.connect(this.changeMouseTarget);
                background.mouseHookerChanged.connect(this.changeMouseTarget);
            }
        }
        Component.onDestruction: {
            if(this.item) this.item.destroy();
            if(this.retiringItem) this.retiringItem.destroy();
        }
        function finishBackendSwap() {
            backendSwapTimeout.stop();
            if(retiringItem) {
                retiringItem.destroy(100);
                retiringItem = null;
            }
            changeMouseTarget();
        }
        function load(url, properties) {
            const com = Qt.createComponent(url);
            if(com.status === Component.Ready) {
                const previousItem = this.item;
                let replacement = null;
                try {
                    replacement = com.createObject(this, properties);
                } catch(e) {
                    this.loadInfoShow(e);
                    return;
                }
                if(!replacement)
                    return;
                if(this.retiringItem)
                    this.retiringItem.destroy();
                this.retiringItem = previousItem;
                this.item = replacement;
                if(this.retiringItem)
                    backendSwapTimeout.restart();
                this.loaded();
            } else if(com.status == Component.Error) {
                this.loadInfoShow(com.errorString());
            }
        }
        function loadInfoShow(info) {
            this.load("backend/InfoShow.qml", {
                wid: background.workshopid,
                type: background.wallpaperType,
                info: info
            });
        }
        function changeMouseTarget() {
           if(backendLoader.item && background.mouseHooker) {
                let re = backendLoader.item.getMouseTarget();
                if(!re)
                    re = null;
                background.mouseHooker.target = background.mouseInput ? re : null;
           }
        }
    }

    function loadSceneStillFallback(generation, requestedSource, assetsPath, projectPath, cacheOnly) {
        pyext.render_scene_fallback(
            projectPath,
            assetsPath,
            background.multiScreenMode,
            background.scaling,
            background.projectPropertyOverrides,
            background.disableParallax,
            background.disableParticles,
            "",
            Boolean(cacheOnly)
        ).then((result) => {
            if(generation !== background.scenePreflightGeneration || requestedSource !== background.wallpaperPath)
                return;
            if(result && result.ok) {
                console.error("DcentWallpapers: animated render unavailable; using real full-resolution still");
                backendLoader.load("backend/Image.qml", {"source": Qt.resolvedUrl(result.path)});
            } else {
                console.error("DcentWallpapers: real scene rendering failed");
                backendLoader.loadInfoShow("The real Wallpaper Engine scene could not be rendered. The thumbnail was not applied.");
            }
            sourceCallback();
        }, () => {
            if(generation !== background.scenePreflightGeneration || requestedSource !== background.wallpaperPath)
                return;
            backendLoader.loadInfoShow("The real Wallpaper Engine scene could not be rendered. The thumbnail was not applied.");
            sourceCallback();
        });
    }

    function loadSceneAnimatedFallback(generation, cacheOnly) {
        const requestedSource = background.wallpaperPath;
        const assetsPath = Common.getAssetsPath(steamlibrary);
        const sourceProjectPath = background.projectPath
                || requestedSource.substring(0, requestedSource.lastIndexOf('/'));
        backendLoader.loadInfoShow("Preparing the real Wallpaper Engine scene…");
        pyext.render_scene_video_fallback(
            sourceProjectPath,
            assetsPath,
            background.multiScreenMode,
            background.scaling,
            background.fps,
            24,
            background.projectPropertyOverrides,
            background.disableParallax,
            background.disableParticles,
            "",
            Boolean(cacheOnly)
        ).then((result) => {
            if(generation !== background.scenePreflightGeneration || requestedSource !== background.wallpaperPath)
                return;
            if(result && result.ok) {
                console.error("DcentWallpapers: loaded real animated scene render");
                backendLoader.load("backend/QtMultimedia.qml", {"source": Qt.resolvedUrl(result.path)});
                sourceCallback();
            } else {
                loadSceneStillFallback(generation, requestedSource, assetsPath, sourceProjectPath, cacheOnly);
            }
        }, () => loadSceneStillFallback(generation, requestedSource, assetsPath, sourceProjectPath, cacheOnly));
    }

    function loadSceneAfterPreflight(generation) {
        const requestedSource = background.wallpaperPath;
        const assetsPath = Common.getAssetsPath(steamlibrary);
        pyext.preflight_scene(requestedSource, assetsPath).then((result) => {
            if(generation !== background.scenePreflightGeneration || requestedSource !== background.wallpaperPath)
                return;
            if(result && result.safe) {
                console.error("DcentWallpapers: isolated scene preflight passed");
                backendLoader.load("backend/Scene.qml", {
                    "source": requestedSource,
                    "assets": assetsPath
                });
                sourceCallback();
            } else {
                console.error("DcentWallpapers: native scene rejected; querying safe cached fallback");
                loadSceneAnimatedFallback(generation, true);
            }
        }, () => {
            if(generation !== background.scenePreflightGeneration || requestedSource !== background.wallpaperPath)
                return;
            console.error("DcentWallpapers: scene preflight failed; querying safe cached fallback");
            loadSceneAnimatedFallback(generation, true);
        });
    }

    function loadBackend() {
        const generation = ++background.scenePreflightGeneration;
        let qmlsource = "";
        let properties = {};


        // check source
        if(!background.source) {
            backendLoader.loadInfoShow("Source is empty. The config may be broken.");
            return;
        }
        // choose backend
        switch (background.wallpaperType) {
            case 'image':
                qmlsource = "backend/Image.qml";
                properties = {};
                break;
            case 'video':
                if(background.videoBackend == Common.VideoBackend.Mpv && background.hasLib)
                    qmlsource = "backend/Mpv.qml";
                else qmlsource = "backend/QtMultimedia.qml";
                properties = {};
                break;
            case 'web':
                qmlsource = "backend/QtWebView.qml";
                properties = {
                    getProject: pyext.get_wallpaper_project,
                    listDirectory: pyext.list_property_directory,
                    projectPath: background.projectPath,
                    workshopId: background.projectIdFromPath(),
                    layoutMode: background.scaling,
                    propertyOverrides: background.projectPropertyOverrides
                };
                break;
            case 'scene':
                if(background.hasLib) {
                    loadSceneAfterPreflight(generation);
                    return;
                } else {
                    backendLoader.loadInfoShow("Plugin helper not found. The real scene cannot be rendered.");
                    return;
                }
                break;
            default:
                backendLoader.loadInfoShow("Not supported wallpaper type");
                return;
        }
        properties['source'] = background.wallpaperPath;
        console.error("load backend: "+qmlsource);
        backendLoader.load(qmlsource, properties);
        sourceCallback();
    }

    function autoPause() {
        background.ok
            ? backendLoader.item.play()
            : backendLoader.item.pause();
    }

    Component.onCompleted: {
        refreshWallpaperOptions();
        // load first backend
        applySource();

        // background signal connect
        background.videoBackendChanged.connect(loadBackend);
        background.okChanged.connect(autoPause);
        background.sourceChanged.connect(applySource);
        background.projectPropertyOverridesChanged.connect(function() {
            if(background.wallpaperType === "web" && backendLoader.item)
                backendLoader.item.propertyOverrides = background.projectPropertyOverrides;
        });

        lauchPauseTimer.start();
        randomizeTimer.start();
    }
}
}
