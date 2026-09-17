import QtQuick 2.5
import QtCore as QtCore
import QtWebEngine 1.10
import QtWebChannel 1.10
import com.github.captsilver.wallpaperEngineKde 1.2
import ".."
import "../WebViewport.js" as WebViewport
import "../WebProperties.js" as WebProperties


Item {
    id: webItem
    anchors.fill: parent
    clip: true

    property url source: ""
    property bool hasLib: background.hasLib
    property int fps: background.fps
    property var getProject
    property var listDirectory

    property string projectPath: ""
    property string workshopId: ""
    property string layoutMode: "fill"
    property int referenceWidth: 1920
    property int referenceHeight: 1080
    property var propertyOverrides: ({})
    property var projectInfo: ({})
    property int projectGeneration: 0
    property int directoryGeneration: 0
    readonly property var viewport: WebViewport.compute(
            Math.max(1, background.spanCanvasWidth),
            Math.max(1, background.spanCanvasHeight),
            layoutMode,
            referenceWidth,
            referenceHeight)

    function deliverUserPropertiesDirect(properties) {
        const payload = JSON.stringify(properties || ({}))
        const encoded = JSON.stringify(payload)
        web.runJavaScript(`
            (function applyDcentProperties(serialized, attempt) {
                var listener = window.wallpaperPropertyListener;
                if (listener && typeof listener.applyUserProperties === 'function') {
                    listener.applyUserProperties(JSON.parse(serialized));
                    return;
                }
                if (attempt < 200)
                    setTimeout(function() { applyDcentProperties(serialized, attempt + 1); }, 50);
            })(${encoded}, 0);
        `)
    }

    function deliverGeneralPropertiesDirect(properties) {
        const payload = JSON.stringify(properties || ({}))
        const encoded = JSON.stringify(payload)
        web.runJavaScript(`
            (function applyDcentGeneral(serialized, attempt) {
                var listener = window.wallpaperPropertyListener;
                if (listener && typeof listener.applyGeneralProperties === 'function') {
                    listener.applyGeneralProperties(JSON.parse(serialized));
                    return;
                }
                if (attempt < 200)
                    setTimeout(function() { applyDcentGeneral(serialized, attempt + 1); }, 50);
            })(${encoded}, 0);
        `)
    }

    function deliverDirectoryFilesDirect(propertyName, files, removed) {
        const nameJson = JSON.stringify(propertyName)
        const filesJson = JSON.stringify(files || [])
        const removedJson = JSON.stringify(removed || [])
        web.runJavaScript(`
            (function(name, added, removedFiles) {
                window.__dcentDirectoryFiles = window.__dcentDirectoryFiles || {};
                window.__dcentDirectoryFiles[name] = added;
                var listener = window.wallpaperPropertyListener;
                if (!listener)
                    return;
                if (added.length && typeof listener.userDirectoryFilesAddedOrChanged === 'function')
                    listener.userDirectoryFilesAddedOrChanged(name, added);
                if (removedFiles.length && typeof listener.userDirectoryFilesRemoved === 'function')
                    listener.userDirectoryFilesRemoved(name, removedFiles);
            })(${nameJson}, ${filesJson}, ${removedJson});
        `)
    }

    function deliverAudioDirect(samples) {
        const samplesJson = JSON.stringify(samples || [])
        web.runJavaScript(`
            if (typeof window.__dcentAudioListener === 'function')
                window.__dcentAudioListener(${samplesJson});
        `)
    }

    function publishDirectoryFiles(generation, spec, files) {
        if (generation !== directoryGeneration)
            return
        const previous = webobj.directoryFiles[spec.name] || []
        const nextDirectories = Object.assign({}, webobj.directoryFiles)
        nextDirectories[spec.name] = files
        webobj.directoryFiles = nextDirectories
        const removed = []
        for (let index = 0; index < previous.length; ++index) {
            if (files.indexOf(previous[index]) < 0)
                removed.push(previous[index])
        }
        if (webobj.loaded)
            webobj.sigDirectoryChanged(spec.name, files, removed)
        deliverDirectoryFilesDirect(spec.name, files, removed)
        if (String(spec.mode || "").toLowerCase() === "fetchall") {
            const properties = Object.assign({}, webobj.userProperties)
            properties[spec.name] = { value: files }
            webobj.userProperties = properties
            if (webobj.loaded)
                webobj.sigUserProperties(properties)
        }
    }

    function refreshDirectoryProperties(definitions, active) {
        const generation = ++directoryGeneration
        for (let index = 0; index < definitions.length; ++index) {
            const spec = definitions[index]
            if (spec.type !== "directory")
                continue
            const value = Object.prototype.hasOwnProperty.call(active, spec.name)
                    ? active[spec.name] : spec.webValue
            if (!value || typeof listDirectory !== "function") {
                publishDirectoryFiles(generation, spec, [])
                continue
            }
            listDirectory(value, spec.fileType || "", 512).then((result) => {
                if (generation !== directoryGeneration)
                    return
                publishDirectoryFiles(generation, spec, result && result.ok ? (result.files || []) : [])
            }).catch(() => publishDirectoryFiles(generation, spec, []))
        }
    }

    function reloadProject() {
        const generation = ++projectGeneration
        if (typeof getProject !== "function" || !projectPath) {
            projectInfo = ({ properties: [], runtimeOverrides: {} })
            rebuildUserProperties()
            return
        }
        getProject(projectPath, workshopId).then((result) => {
            if (generation !== projectGeneration)
                return
            projectInfo = result && result.ok ? result : ({ properties: [], runtimeOverrides: {} })
            rebuildUserProperties()
        }).catch((error) => {
            if (generation !== projectGeneration)
                return
            console.error("DcentWallpapers: web property load failed: " + error)
            projectInfo = ({ properties: [], runtimeOverrides: {} })
            rebuildUserProperties()
        })
    }

    function rebuildUserProperties() {
        const definitions = projectInfo.properties || []
        const active = propertyOverrides && typeof propertyOverrides === "object" ? propertyOverrides : ({})
        const properties = ({})
        const known = ({})
        for (let index = 0; index < definitions.length; ++index) {
            const spec = definitions[index]
            if (!spec.editable)
                continue
            known[spec.name] = true
            let value = WebProperties.effectiveValue(spec, definitions, active)
            properties[spec.name] = { value: value }
        }
        const runtime = projectInfo.runtimeOverrides || ({})
        for (const name in runtime) {
            if (!known[name])
                properties[name] = { value: Object.prototype.hasOwnProperty.call(active, name) ? active[name] : runtime[name] }
        }
        for (const extraName in active) {
            if (!Object.prototype.hasOwnProperty.call(properties, extraName))
                properties[extraName] = { value: active[extraName] }
        }
        webobj.userProperties = properties
        if (webobj.loaded)
            webobj.sigUserProperties(properties)
        deliverUserPropertiesDirect(properties)
        refreshDirectoryProperties(definitions, active)
    }

    function publishGeneralProperties() {
        webobj.generalProperties = { fps: Math.max(1, fps) }
        if (webobj.loaded)
            webobj.sigGeneralProperties(webobj.generalProperties)
        deliverGeneralPropertiesDirect(webobj.generalProperties)
    }

    onFpsChanged: publishGeneralProperties()
    onSourceChanged: {
        if (web.initialized && web.url !== source)
            web.url = source
    }
    onProjectPathChanged: reloadProject()
    onWorkshopIdChanged: reloadProject()
    onPropertyOverridesChanged: rebuildUserProperties()

    WebAudioBridge {
        id: audioBridge
        enabled: background.systemAudioCapture
        onAudioBuffer: function(samples) {
            if (webobj.loaded)
                webobj.sigAudio(samples)
            webItem.deliverAudioDirect(samples)
        }
    }

    /* Where the paused WebEngineView stores its last frame. The grab result's
       own url uses Qt's internal "itemgrabber:" protocol, which Qt Quick's
       Image cannot load, so the frame is written next to the other runtime
       data and loaded from disk. */
    readonly property string pauseSnapshotDirectory: {
        try {
            var base = QtCore.StandardPaths.writableLocation(QtCore.StandardPaths.CacheLocation)
            if (base && base.length)
                return base
        } catch (e) {
            // fall through to the temporary directory
        }
        return "/tmp"
    }
    readonly property string pauseSnapshotPath: pauseSnapshotDirectory + "/dcent-pause-snapshot-" + Screen.virtualX + "x" + Screen.virtualY + ".png"

    Image {
        id: pauseImage
        x: background.spanCanvasX + webItem.viewport.x
        y: background.spanCanvasY + webItem.viewport.y
        width: webItem.viewport.renderWidth
        height: webItem.viewport.renderHeight
        transform: Scale {
            origin.x: 0
            origin.y: 0
            yScale: webItem.viewport.verticalTransform
        }
        cache: false
        visible: false
        enabled: false
        // Only hide the frozen view once the still is really on screen, so a
        // failed snapshot can never leave an empty desktop behind.
        onStatusChanged: {
            if (status === Image.Ready && web.paused) {
                pauseImage.visible = true
                web.visible = false
            }
        }
    }

    QtObject {
        id: webobj
        WebChannel.id: "wpeQml"
        signal sigGeneralProperties(var properties)
        signal sigUserProperties(var properties)
        signal sigAudio(var audioArray)
        signal sigDirectoryChanged(string propertyName, var addedOrChanged, var removed)
        property bool loaded: false
        property var userProperties: ({})
        property var generalProperties: ({ fps: 24 })
        property var directoryFiles: ({})
        onLoadedChanged: {
            if (!loaded)
                return
            webItem.publishGeneralProperties()
            webItem.rebuildUserProperties()
        }
    }

    WebChannel {
        id: channel
        registeredObjects: [webobj]
    }

    WebEngineView {
        id: web
        url: "about:blank"
        x: background.spanCanvasX + webItem.viewport.x
        y: background.spanCanvasY + webItem.viewport.y
        width: webItem.viewport.renderWidth
        height: webItem.viewport.renderHeight
        zoomFactor: webItem.viewport.scaleX
        transform: Scale {
            origin.x: 0
            origin.y: 0
            yScale: webItem.viewport.verticalTransform
        }
        enabled: true
        audioMuted: background.mute
        activeFocusOnPress: true

        property bool paused: false
        property bool initialized: false

        Component.onCompleted: {
            settings.fullscreenSupportEnabled = true
            settings.autoLoadIconsForPage = false
            settings.printElementBackgrounds = false
            settings.playbackRequiresUserGesture = false
            settings.pdfViewerEnabled = false
            settings.showScrollBars = false
            settings.localContentCanAccessRemoteUrls = false
            // Keep Chromium's broad file:// disclosure capability disabled.
            // Web projects that require sibling assets are loaded only when
            // Chromium permits them under the same local origin.
            settings.localContentCanAccessFileUrls = false
            settings.allowGeolocationOnInsecureOrigins = false

            userScripts.collection = [
                {
                    injectionPoint: WebEngineScript.DocumentCreation,
                    worldId: WebEngineScript.MainWorld,
                    name: "DcentAudio",
                    sourceCode: `
                        window.__dcentDirectoryFiles = window.__dcentDirectoryFiles || {};
                        window.wallpaperRegisterAudioListener = function(listener) {
                            window.__dcentAudioListener = listener;
                        };
                        window.wallpaperRequestRandomFileForProperty = function(propertyName, callback) {
                            var files = window.__dcentDirectoryFiles[propertyName] || [];
                            var value = files.length ? files[Math.floor(Math.random() * files.length)] : '';
                            if (typeof callback === 'function')
                                callback(propertyName, value);
                            return value;
                        };
                    `
                },
                {
                    injectionPoint: WebEngineScript.Deferred,
                    worldId: WebEngineScript.MainWorld,
                    name: "DcentHideWallpaperDiagnostics",
                    sourceCode: `
                        (function hideWallpaperDiagnostics(attempt) {
                            if (window.log && window.log.htmlElement) {
                                window.log.hide();
                                window.log.show = function() {};
                                return;
                            }
                            if (attempt < 100)
                                setTimeout(function() { hideWallpaperDiagnostics(attempt + 1); }, 50);
                        })(0);
                    `
                }
            ]
            initialized = true
            background.nowBackend = "QtWebEngine"
            Qt.callLater(function() {
                web.url = webItem.source
            })
            webItem.reloadProject()
        }

        onLoadingChanged: (loadingInfo) => {
            if (loadingInfo.status === WebEngineView.LoadSucceededStatus) {
                if (paused) {
                    webItem.play()
                    webItem.pause()
                }
                webItem.deliverGeneralPropertiesDirect(webobj.generalProperties)
                webItem.deliverUserPropertiesDirect(webobj.userProperties)
                background.sig_backendFirstFrame("QtWebEngine")
            }
        }

        onPausedChanged: {
            if (paused) {
                pauseTimer.start()
            } else {
                pauseImage.visible = false
                pauseImage.source = ""
                web.visible = true
                web.lifecycleState = WebEngineView.LifecycleState.Active
            }
        }
    }

    Timer {
        id: pauseTimer
        running: false
        repeat: false
        interval: 300
        onTriggered: {
            const snapshotPath = webItem.pauseSnapshotPath
            web.grabToImage(function(result) {
                if (!web.paused || !web.visible)
                    return
                // result.url is an internal "itemgrabber:" url that Image
                // cannot load, so persist the frame instead. pauseImage hides
                // the frozen view once the file really loaded; if either step
                // fails the frozen view stays visible with its last frame.
                if (!result || !result.saveToFile(snapshotPath)) {
                    web.lifecycleState = WebEngineView.LifecycleState.Frozen
                    return
                }
                pauseImage.source = ""
                pauseImage.source = "file://" + snapshotPath
                web.lifecycleState = WebEngineView.LifecycleState.Frozen
            })
        }
    }

    Component.onCompleted: {
        publishGeneralProperties()
        reloadProject()
    }

    function play() {
        web.paused = false
    }

    function pause() {
        web.paused = true
    }
    function stopRenderer() {
        try { pauseTimer.stop(); } catch(e) {}
        try { web.stop(); } catch(e) {}
        try { web.url = "about:blank"; } catch(e) {}
        try { webItem.visible = false; } catch(e) {}
    }

    function getMouseTarget() {
        web.activeFocusOnPress = true
        return Qt.binding(function() { return web.children[0] })
    }
}
