pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as Dialogs
import QtWebEngine
import org.kde.kirigami as Kirigami
import "../data/library.js" as LibraryData
import "PropertyConditions.js" as PropertyConditions

RowLayout {
    id: root
    spacing: 14

    readonly property color steamBlue: Kirigami.Theme.highlightColor
    readonly property color steamBlueStrong: Kirigami.Theme.highlightColor
    readonly property color appSurface: Kirigami.Theme.backgroundColor
    readonly property color panelSurface: Kirigami.Theme.alternateBackgroundColor
    readonly property color cardSurface: Kirigami.Theme.alternateBackgroundColor
    readonly property color cardHover: Qt.lighter(Kirigami.Theme.alternateBackgroundColor, 1.12)
    readonly property color borderSubtle: Kirigami.Theme.disabledTextColor
    readonly property color textPrimary: Kirigami.Theme.textColor
    readonly property color textMuted: Kirigami.Theme.disabledTextColor
    property bool inspectorCollapsed: false
    readonly property bool compactLayout: width < 900

    property var configDialog
    property var wallpaperConfiguration: configDialog ? configDialog.wallpaperConfiguration : null
    property var screen: null
    property string selectedScreenName: ""
    readonly property bool kdeAllScreensEnabled: Boolean(configDialog && typeof configDialog.allScreens !== "undefined" && configDialog.allScreens)
    signal configurationChanged
    property string applyStatus: "Select a wallpaper"
    property string cfg_WorkshopRoot: "/data/SteamLibrary/steamapps/workshop/content/431960"
    property string cfg_WallpaperPath: ""
    property string cfg_PreviewPath: ""
    property string cfg_MediaPath: ""
    property string cfg_WallpaperType: "scene"
    property string cfg_Scaling: "fit"
    property bool cfg_Muted: true
    property int cfg_Volume: 0
    property int cfg_Fps: 30
    property bool cfg_DisableMouse: false
    property bool cfg_DisableParallax: false
    property bool cfg_DisableParticles: false
    property string cfg_PropertyOverrides: ""
    property string cfg_MultiScreenMode: "mirror"
    property int cfg_VirtualDesktopX: 0
    property int cfg_VirtualDesktopY: 0
    property int cfg_VirtualDesktopWidth: 0
    property int cfg_VirtualDesktopHeight: 0

    property string cfg_SteamLibraryPath: "/data/SteamLibrary"
    property string cfg_WallpaperWorkShopId: ""
    property string cfg_WallpaperSource: ""
    property string cfg_BackgroundColor: "black"
    property int cfg_DisplayMode: 0
    property int cfg_Rotation: 0
    property int cfg_PauseMode: 0
    property bool cfg_PauseFilterByScreen: true
    property bool cfg_PauseOnBatPower: false
    property int cfg_PauseBatPercent: 0
    property int cfg_SortMode: 0
    property int cfg_FilterMode: 0
    property int cfg_VideoBackend: 0
    property bool cfg_MuteAudio: true
    property bool cfg_SystemAudioCapture: true
    property bool cfg_RandomizeWallpaper: false
    property bool cfg_NoRandomWhilePaused: false
    property bool cfg_MpvStats: false
    property bool cfg_MouseInput: true
    property int cfg_SwitchTimer: 120
    property int cfg_ResumeTime: 300
    property real cfg_Speed: 1.0
    property string cfg_FilterStr: ""
    property bool cfg_PerOptChanged: false
    property string cfg_CustomConf: ""

    property var selectedItem: null
    readonly property string selectedPreviewPath: selectedItem
            ? String(selectedItem.preview || "").replace(/^file:\/\//, "") : ""
    property string appliedWorkshopId: ""
    property int selectionGeneration: 0
    property int stagedSelectionGeneration: -1
    property string stagedWorkshopId: ""
    property int sceneRenderSerial: 0
    property string activeSceneRenderId: ""
    property bool sceneChecking: false
    property bool applyAfterSceneCheck: false
    property bool applyBlocked: false
    property bool selectedSourceReady: false
    property bool loginApplying: false
    property string loginStatus: ""
    property bool propertiesLoading: false
    property bool propertiesDirty: false
    property bool sceneNeedsRestage: false
    readonly property bool canApplySelection: selectedItem !== null
            && !(selectedItem.online && !selectedItem.installed)
            && !applyBlocked
            && (selectedSourceReady || sceneNeedsRestage || sceneChecking || propertiesLoading)
    property int propertyRevision: 0
    property int propertySaveGeneration: 0
    property string propertyStatus: ""
    property string propertyCapabilityStatus: ""
    property string propertyQuery: ""
    property var wallpaperProperties: []
    property var visibleWallpaperProperties: []
    property var propertyValues: ({})
    property var userPropertyOverrides: ({})
    property var presetPropertyOverrides: ({})
    property var runtimePropertyOverrides: ({})
    property string browsePropertyName: ""
    property string browseFileType: ""
    property string colorPropertyName: ""
    property int colorComponentCount: 3
    property bool onlineMode: false
    property bool onlineLoading: false
    property bool onlineAwaitingInstall: false
    property int onlinePage: 1
    property bool onlineHasMore: false
    property int onlineTotal: 0
    property int onlineSearchGeneration: 0
    property string onlineStatus: ""
    property bool steamApiKeyConfigured: false
    property string steamApiKeyStatus: ""
    property var localCatalog: LibraryData.wallpapers
    property bool localCatalogRefreshing: false
    property int localCatalogGeneration: 0

    Pyext { id: scenePreflightBridge }

    onScreenChanged: rememberScreenTarget(screen)
    Connections {
        target: root.configDialog
        ignoreUnknownSignals: true
        function onSelectedScreenChanged() {
            root.rememberScreenTarget(root.configDialog.selectedScreen)
        }
    }

    Timer {
        id: propertySaveTimer
        interval: 650
        repeat: false
        onTriggered: root.persistWallpaperProperties()
    }

    Timer {
        id: onlineSearchTimer
        interval: 450
        repeat: false
        onTriggered: root.performOnlineSearch(1)
    }

    Timer {
        id: workshopInstallTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: root.checkSelectedWorkshopInstall()
    }

    Dialog {
        id: workshopDetailsDialog
        objectName: "embeddedWorkshopBrowser"
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(root.width * 0.92, 1180)
        height: Math.min(root.height * 0.92, 820)
        x: Math.max(0, (parent.width - width) / 2)
        y: Math.max(0, (parent.height - height) / 2)
        title: "Steam Workshop"
        standardButtons: Dialog.Close
        contentItem: ColumnLayout {
            spacing: 10
            Kirigami.Heading {
                Layout.fillWidth: true
                text: "Steam Community"
                level: 3
            }
            Label {
                Layout.fillWidth: true
                text: "Sign in if needed, then use Steam's Subscribe button below. The page stays inside this KDE plugin."
                color: root.textMuted
                wrapMode: Text.WordWrap
            }
            WebEngineView {
                id: workshopWebView
                objectName: "embeddedWorkshopWebView"
                Layout.fillWidth: true
                Layout.fillHeight: true
                url: "about:blank"
                settings.fullScreenSupportEnabled: false
                settings.javascriptCanOpenWindows: false
                onLoadingChanged: function(loadRequest) {
                    if (loadRequest.status === WebEngineView.LoadStartedStatus)
                        root.onlineStatus = "Loading official Workshop page…"
                    else if (loadRequest.status === WebEngineView.LoadSucceededStatus)
                        root.onlineStatus = "Workshop page ready • Subscribe here and Dcent will detect the download"
                    else if (loadRequest.status === WebEngineView.LoadFailedStatus)
                        root.onlineStatus = "The official Workshop page could not be loaded"
                }
            }
        }
    }

    Dialogs.FileDialog {
        id: propertyFileDialog
        title: "Choose a file for " + root.browsePropertyName
        nameFilters: root.browseFileType === "video"
                     ? ["Video files (*.mp4 *.webm *.mkv *.mov *.avi *.m4v)", "All files (*)"]
                     : (root.browseFileType === "image"
                        ? ["Image files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.tif *.tiff)", "All files (*)"]
                        : ["All files (*)"])
        onAccepted: root.setWallpaperProperty(root.browsePropertyName, selectedFile.toLocalFile())
    }

    Dialogs.FolderDialog {
        id: propertyFolderDialog
        title: "Choose a folder"
        onAccepted: root.setWallpaperProperty(root.browsePropertyName, selectedFolder.toLocalFile())
    }

    Dialogs.ColorDialog {
        id: propertyColorDialog
        title: "Choose Wallpaper Engine color"
        onAccepted: root.setWallpaperProperty(
            root.colorPropertyName,
            root.wallpaperColorString(selectedColor, root.colorComponentCount)
        )
    }

    function normalizedCatalogItem(item, isOnline) {
        return {
            title: String(item.title || ("Workshop " + item.workshopId)),
            workshopId: String(item.workshopId || ""),
            kind: String(item.kind || (isOnline ? "workshop" : "unknown")),
            renderKind: String(item.renderKind || ""),
            support: String(item.support || (item.installed ? "Installed" : "Available on Steam")),
            folder: String(item.folder || ""),
            preview: String(item.preview || ""),
            media: String(item.media || ""),
            sizeBytes: Number(item.sizeBytes || item.size || 0),
            previewWidth: Number(item.previewWidth || 0),
            previewHeight: Number(item.previewHeight || 0),
            online: Boolean(isOnline),
            installed: isOnline ? Boolean(item.installed) : true,
            author: String(item.author || ""),
            authorUrl: String(item.authorUrl || ""),
            creator: String(item.creator || ""),
            description: String(item.description || ""),
            tagsText: Array.isArray(item.tags) ? item.tags.join(" • ") : String(item.tagsText || ""),
            updatedEpoch: Number(item.updatedEpoch || 0),
            subscriptions: Number(item.subscriptions || 0),
            views: Number(item.views || 0),
            rating: Number(item.rating || 0),
            workshopUrl: String(item.workshopUrl || ("https://steamcommunity.com/sharedfiles/filedetails/?id=" + item.workshopId))
        }
    }

    function onlineSortValue() {
        return ["trend", "toprated", "mostrecent", "mostsubscribed"][workshopSortPicker.currentIndex] || "trend"
    }

    function switchCatalogMode(useOnline) {
        onlineMode = Boolean(useOnline)
        onlinePage = 1
        onlineAwaitingInstall = false
        workshopInstallTimer.stop()
        if (onlineMode)
            performOnlineSearch(1)
        else
            rebuildCatalog()
    }

    function performOnlineSearch(page) {
        page = Math.max(1, Number(page || 1))
        onlinePage = page
        onlineLoading = true
        onlineStatus = "Searching Steam Workshop…"
        var generation = ++onlineSearchGeneration
        var kind = typeFilter.currentText.toLowerCase()
        scenePreflightBridge.search_workshop(
            searchField.text.trim(), page, onlineSortValue(), kind, cfg_WorkshopRoot
        ).then(
            function(result) {
                if (generation !== root.onlineSearchGeneration || !root.onlineMode)
                    return
                root.onlineLoading = false
                if (!result || !result.ok) {
                    root.onlineStatus = result && result.error ? result.error : "Steam Workshop search failed"
                    root.onlineHasMore = false
                    return
                }
                catalogModel.clear()
                var items = result.items || []
                for (var index = 0; index < items.length; ++index)
                    catalogModel.append(root.normalizedCatalogItem(items[index], true))
                root.onlineTotal = Number(result.total || items.length)
                root.onlineHasMore = Boolean(result.hasMore)
                root.onlineStatus = result.status || (root.onlineTotal + " Workshop wallpapers")
                resultCount.text = root.onlineTotal + " online"
                grid.contentY = 0
            },
            function(error) {
                if (generation !== root.onlineSearchGeneration)
                    return
                root.onlineLoading = false
                root.onlineStatus = "Steam Workshop search failed"
            }
        )
    }

    function mergeLocalCatalogItems(discovered) {
        var cached = ({})
        for (var currentIndex = 0; currentIndex < localCatalog.length; ++currentIndex)
            cached[String(localCatalog[currentIndex].workshopId)] = localCatalog[currentIndex]
        for (var bundledIndex = 0; bundledIndex < LibraryData.wallpapers.length; ++bundledIndex) {
            var bundled = LibraryData.wallpapers[bundledIndex]
            if (!cached[String(bundled.workshopId)])
                cached[String(bundled.workshopId)] = bundled
        }
        var merged = []
        for (var index = 0; index < discovered.length; ++index) {
            var fresh = discovered[index]
            var old = cached[String(fresh.workshopId)] || ({})
            var item = ({})
            for (var oldKey in old)
                item[oldKey] = old[oldKey]
            for (var freshKey in fresh)
                item[freshKey] = fresh[freshKey]
            if (Number(fresh.sizeBytes || fresh.size || 0) <= 0 && Number(old.sizeBytes || old.size || 0) > 0)
                item.sizeBytes = Number(old.sizeBytes || old.size)
            if (Number(fresh.previewWidth || 0) <= 0 && Number(old.previewWidth || 0) > 0)
                item.previewWidth = Number(old.previewWidth)
            if (Number(fresh.previewHeight || 0) <= 0 && Number(old.previewHeight || 0) > 0)
                item.previewHeight = Number(old.previewHeight)
            merged.push(item)
        }
        return merged
    }

    function refreshLocalCatalog() {
        var generation = ++localCatalogGeneration
        var workshopRoot = cfg_WorkshopRoot
        localCatalogRefreshing = true
        scenePreflightBridge.list_local_workshop_items(workshopRoot).then(
            function(result) {
                if (generation !== root.localCatalogGeneration || workshopRoot !== root.cfg_WorkshopRoot)
                    return
                root.localCatalogRefreshing = false
                if (!result || !result.ok)
                    return
                root.localCatalog = root.mergeLocalCatalogItems(result.items || [])
                if (!root.onlineMode)
                    root.rebuildCatalog()
            },
            function(error) {
                if (generation === root.localCatalogGeneration && workshopRoot === root.cfg_WorkshopRoot)
                    root.localCatalogRefreshing = false
            }
        )
    }

    function pathBelongsToItem(path, folder) {
        var normalizedPath = String(path || "").replace(/^file:\/\//, "").replace(/\/+$/, "")
        var normalizedFolder = String(folder || "").replace(/^file:\/\//, "").replace(/\/+$/, "")
        if (!normalizedPath || !normalizedFolder)
            return false
        return normalizedPath === normalizedFolder || normalizedPath.indexOf(normalizedFolder + "/") === 0
    }

    function rebuildCatalog() {
        if (onlineMode) {
            onlineSearchTimer.restart()
            return
        }
        catalogModel.clear()
        var query = searchField.text.trim().toLowerCase()
        var filter = typeFilter.currentText.toLowerCase()
        for (var i = 0; i < localCatalog.length; ++i) {
            var item = localCatalog[i]
            var matchesText = query.length === 0 || item.title.toLowerCase().indexOf(query) >= 0 || item.workshopId.indexOf(query) >= 0
            var matchesType = filter === "all" || item.kind === filter
            if (matchesText && matchesType)
                catalogModel.append(normalizedCatalogItem(item, false))
            if (!selectedItem && (item.workshopId === cfg_WallpaperWorkShopId
                    || (!cfg_WallpaperWorkShopId && pathBelongsToItem(cfg_WallpaperPath, item.folder))))
                selectedItem = normalizedCatalogItem(item, false)
        }
        resultCount.text = catalogModel.count + " installed"
    }

    function cloneObject(value) {
        var result = ({})
        if (!value || typeof value !== "object")
            return result
        for (var key in value)
            result[key] = value[key]
        return result
    }

    function objectsEqual(left, right) {
        return JSON.stringify(left) === JSON.stringify(right)
    }

    function propertySpec(name) {
        for (var index = 0; index < wallpaperProperties.length; ++index) {
            if (wallpaperProperties[index].name === name)
                return wallpaperProperties[index]
        }
        return null
    }

    function wallpaperPropertyValue(name, fallbackValue) {
        var revision = propertyRevision
        return Object.prototype.hasOwnProperty.call(propertyValues, name) ? propertyValues[name] : fallbackValue
    }

    function propertyConditionValues() {
        var values = ({})
        for (var index = 0; index < wallpaperProperties.length; ++index) {
            var spec = wallpaperProperties[index]
            values[spec.name] = {
                value: wallpaperPropertyValue(spec.name, spec.default),
                min: spec.min,
                max: spec.max,
                text: spec.label
            }
        }
        return values
    }

    function refreshVisibleWallpaperProperties() {
        var query = propertyQuery.trim().toLowerCase()
        var conditions = propertyConditionValues()
        var visible = []
        for (var index = 0; index < wallpaperProperties.length; ++index) {
            var spec = wallpaperProperties[index]
            var haystack = (spec.label + " " + spec.name + " " + spec.type).toLowerCase()
            if (query && haystack.indexOf(query) < 0)
                continue
            if (spec.condition && !PropertyConditions.evaluate(spec.condition, conditions))
                continue
            visible.push(spec)
        }
        visibleWallpaperProperties = visible
    }

    function rebuildRuntimePropertyOverrides(publishCommitted) {
        var runtime = cloneObject(presetPropertyOverrides)
        for (var name in userPropertyOverrides)
            runtime[name] = userPropertyOverrides[name]
        runtimePropertyOverrides = runtime
        if (publishCommitted && selectedItem && selectedSourceReady
                && stagedSelectionGeneration === selectionGeneration
                && stagedWorkshopId === selectedItem.workshopId) {
            cfg_PropertyOverrides = Object.keys(runtime).length > 0 ? JSON.stringify(runtime) : ""
            configurationChanged()
        }
        propertyRevision += 1
        refreshVisibleWallpaperProperties()
    }

    function countLabel(count, singular, plural) {
        return count + " " + (count === 1 ? singular : plural)
    }

    function propertyCapabilities(info) {
        var labels = {
            bool: ["toggle", "toggles"], slider: ["slider", "sliders"], combo: ["choice", "choices"], color: ["color", "colors"],
            textinput: ["text field", "text fields"], file: ["file", "files"], directory: ["folder", "folders"], scenetexture: ["texture", "textures"],
            usershortcut: ["shortcut", "shortcuts"], unknown: ["custom value", "custom values"]
        }
        var parts = []
        var counts = info && info.propertyTypeCounts ? info.propertyTypeCounts : ({})
        for (var type in counts) {
            if (labels[type])
                parts.push(countLabel(counts[type], labels[type][0], labels[type][1]))
        }
        if (info && info.supportsAudioProcessing)
            parts.push("audio reactive")
        if (info && info.supportsVideo)
            parts.push("video textures")
        if (info && info.locales && info.locales.length > 0)
            parts.push(info.locales.length + " languages")
        return parts.join(" • ")
    }

    function applyProjectInfo(info, savedStatus) {
        wallpaperProperties = info && info.properties ? info.properties : []
        userPropertyOverrides = cloneObject(info && info.userOverrides ? info.userOverrides : {})
        presetPropertyOverrides = cloneObject(info && info.presetOverrides ? info.presetOverrides : {})
        var values = ({})
        for (var index = 0; index < wallpaperProperties.length; ++index)
            values[wallpaperProperties[index].name] = wallpaperProperties[index].value
        propertyValues = values
        propertiesLoading = false
        propertiesDirty = false
        propertyCapabilityStatus = propertyCapabilities(info || {})
        rebuildRuntimePropertyOverrides()
        if (savedStatus)
            propertyStatus = savedStatus
        else if (wallpaperProperties.length > 0) {
            var editableCount = info.editablePropertyCount || 0
            propertyStatus = editableCount + " of " + wallpaperProperties.length + " "
                    + (wallpaperProperties.length === 1 ? "property" : "properties") + " editable"
        }
        else if (Object.keys(presetPropertyOverrides).length > 0)
            propertyStatus = "Preset runtime values loaded"
        else
            propertyStatus = "No project-specific properties"
    }

    function loadWallpaperProject(generation, item, routeAfterLoad) {
        propertiesLoading = true
        propertyStatus = "Reading Wallpaper Engine properties…"
        scenePreflightBridge.get_wallpaper_project(item.folder, item.workshopId).then(
            function(info) {
                if (generation !== root.selectionGeneration || !root.selectedItem || root.selectedItem.workshopId !== item.workshopId)
                    return
                root.applyProjectInfo(info || {}, "")
                if (routeAfterLoad)
                    root.routeWallpaper(generation, item, info || {})
                else if (root.applyAfterSceneCheck)
                    root.applyNow()
            },
            function(error) {
                if (generation !== root.selectionGeneration)
                    return
                root.propertiesLoading = false
                root.propertyStatus = "Property parser unavailable"
                root.wallpaperProperties = []
                root.visibleWallpaperProperties = []
                root.userPropertyOverrides = ({})
                root.presetPropertyOverrides = ({})
                root.rebuildRuntimePropertyOverrides()
                if (routeAfterLoad)
                    root.routeWallpaper(generation, item, {})
                else if (root.applyAfterSceneCheck)
                    root.applyNow()
            }
        )
    }

    function setWallpaperProperty(name, value) {
        var spec = propertySpec(name)
        if (!spec || !spec.editable)
            return
        var values = cloneObject(propertyValues)
        values[name] = value
        propertyValues = values
        var changed = cloneObject(userPropertyOverrides)
        if (objectsEqual(value, spec.presetValue))
            delete changed[name]
        else
            changed[name] = value
        userPropertyOverrides = changed
        propertiesDirty = true
        propertyStatus = "Saving property changes…"
        if (selectedItem && selectedItem.kind === "scene")
            invalidateSceneRender("Scene properties changed • Apply will rebuild the animated scene")
        rebuildRuntimePropertyOverrides(true)
        propertySaveTimer.restart()
    }

    function persistWallpaperProperties() {
        if (!selectedItem || propertiesLoading)
            return
        var item = selectedItem
        var generation = ++propertySaveGeneration
        scenePreflightBridge.write_wallpaper_properties(item.workshopId, item.folder, userPropertyOverrides).then(
            function(info) {
                if (generation !== root.propertySaveGeneration || !root.selectedItem || root.selectedItem.workshopId !== item.workshopId)
                    return
                root.applyProjectInfo(info || {}, "Properties saved for this wallpaper")
                root.cfg_PerOptChanged = !root.cfg_PerOptChanged
                root.configurationChanged()
            },
            function(error) {
                if (generation !== root.propertySaveGeneration)
                    return
                root.propertyStatus = "Could not save properties"
            }
        )
    }

    function resetWallpaperProperties() {
        if (!selectedItem || propertiesLoading)
            return
        propertySaveTimer.stop()
        var item = selectedItem
        if (item.kind === "scene")
            invalidateSceneRender("Resetting scene properties…")
        var generation = ++propertySaveGeneration
        propertyStatus = "Resetting properties…"
        scenePreflightBridge.reset_wallpaper_properties(item.workshopId, item.folder).then(
            function(info) {
                if (generation !== root.propertySaveGeneration || !root.selectedItem || root.selectedItem.workshopId !== item.workshopId)
                    return
                root.applyProjectInfo(info || {}, "Project defaults restored")
                root.sceneNeedsRestage = item.kind === "scene"
                root.cfg_PerOptChanged = !root.cfg_PerOptChanged
                root.configurationChanged()
            },
            function(error) { root.propertyStatus = "Could not reset properties" }
        )
    }

    function typedScalarKey(value) {
        if (value === null || value === undefined)
            return "null"
        if (typeof value === "number")
            return "number:" + String(value)
        if (typeof value === "boolean")
            return "boolean:" + (value ? "true" : "false")
        if (typeof value === "string")
            return "string:" + JSON.stringify(value)
        return typeof value + ":" + JSON.stringify(value)
    }

    function comboPropertyIndex(spec) {
        var value = wallpaperPropertyValue(spec.name, spec.default)
        var options = comboPropertyOptions(spec)
        var valueKey = typedScalarKey(value)
        for (var index = 0; index < options.length; ++index) {
            if (typedScalarKey(options[index].value) === valueKey)
                return index
        }
        return 0
    }

    function comboPropertyOptions(spec) {
        var revision = propertyRevision
        var conditions = propertyConditionValues()
        var sourceOptions = spec.options || []
        var options = []
        for (var index = 0; index < sourceOptions.length; ++index) {
            var option = sourceOptions[index]
            if (!option.condition || PropertyConditions.evaluate(option.condition, conditions))
                options.push(option)
        }
        return options
    }

    function assetPropertyIndex(spec) {
        var options = spec.assetOptions || []
        var value = String(wallpaperPropertyValue(spec.name, spec.default) || "")
        for (var index = 0; index < options.length; ++index) {
            var optionValue = String(options[index].value || "")
            if (optionValue === value || (value.length > 0 && optionValue.endsWith("/" + value)))
                return index
        }
        return -1
    }

    function friendlyPropertyLabel(spec) {
        var name = String(spec && spec.name ? spec.name : "")
        var label = String(spec && spec.label ? spec.label : name).trim()
        if (label && label !== name && label.indexOf("_") < 0)
            return label
        var cleaned = (label || name)
                .replace(/^ui_(?:browse_)?properties_/, "")
                .replace(/^ui_/, "")
                .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
                .replace(/[_-]+/g, " ")
                .trim()
                .toLowerCase()
        if (cleaned === "scheme color")
            return "Color scheme"
        return cleaned ? cleaned.charAt(0).toUpperCase() + cleaned.slice(1) : "Property"
    }

    function qmlColor(value) {
        if (typeof value === "string" && value.charAt(0) === "#")
            return value
        var parts = String(value || "1 1 1").trim().split(/\s+/)
        return Qt.rgba(Number(parts[0] || 1), Number(parts[1] || 1), Number(parts[2] || 1), Number(parts[3] || 1))
    }

    function colorHexByte(value) {
        return Math.max(0, Math.min(255, Math.round(Number(value) * 255))).toString(16).padStart(2, "0").toUpperCase()
    }

    function wallpaperColorDisplay(value, components) {
        var color = qmlColor(value)
        var result = "#" + colorHexByte(color.r) + colorHexByte(color.g) + colorHexByte(color.b)
        if (Number(components || 3) >= 4)
            result += colorHexByte(color.a)
        return result
    }

    function colorNumber(value) {
        var text = Number(value).toFixed(4)
        return text.replace(/0+$/, "").replace(/\.$/, "") || "0"
    }

    function wallpaperColorString(color, components) {
        var result = [colorNumber(color.r), colorNumber(color.g), colorNumber(color.b)]
        if (components > 3)
            result.push(colorNumber(color.a))
        return result.join(" ")
    }


    function openColorEditor(spec) {
        colorPropertyName = spec.name
        colorComponentCount = String(wallpaperPropertyValue(spec.name, spec.default)).trim().split(/\s+/).length > 3 ? 4 : 3
        propertyColorDialog.selectedColor = qmlColor(wallpaperPropertyValue(spec.name, spec.default))
        propertyColorDialog.open()
    }

    function openPropertyFile(spec) {
        browsePropertyName = spec.name
        browseFileType = String(spec.fileType || "").toLowerCase()
        if (spec.type === "directory")
            propertyFolderDialog.open()
        else
            propertyFileDialog.open()
    }

    function stageSource(kind, media) {
        cfg_MediaPath = media || ""
        cfg_WallpaperType = kind
        cfg_WallpaperSource = media ? media + "+" + kind : ""
    }

    function stageSelectedSource(generation, item, kind, media, preview) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return false
        cfg_WallpaperPath = item.folder
        cfg_PreviewPath = preview || item.preview.replace("file://", "")
        cfg_SteamLibraryPath = cfg_WorkshopRoot.substring(0, cfg_WorkshopRoot.indexOf("/steamapps/"))
        cfg_WallpaperWorkShopId = item.workshopId
        cfg_PropertyOverrides = Object.keys(runtimePropertyOverrides).length > 0
                ? JSON.stringify(runtimePropertyOverrides) : ""
        stageSource(kind, media)
        stagedSelectionGeneration = generation
        stagedWorkshopId = item.workshopId
        selectedSourceReady = true
        applyBlocked = false
        configurationChanged()
        return true
    }

    function nextSceneRenderId(kind, generation, item) {
        sceneRenderSerial += 1
        return kind + ":" + generation + ":" + sceneRenderSerial + ":" + item.workshopId
    }

    function sceneRenderMatches(generation, item, renderId) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return false
        return !renderId || activeSceneRenderId === renderId
    }

    function cancelActiveSceneRender() {
        var renderId = activeSceneRenderId
        if (!renderId)
            return false
        activeSceneRenderId = ""
        scenePreflightBridge.cancel_scene_render(renderId)
        return true
    }

    function invalidateSceneRender(status) {
        cancelActiveSceneRender()
        stagedSelectionGeneration = -1
        stagedWorkshopId = ""
        sceneChecking = false
        applyAfterSceneCheck = false
        applyBlocked = false
        if (selectedItem && selectedItem.kind === "scene") {
            sceneNeedsRestage = true
            selectedSourceReady = false
        }
        if (status)
            applyStatus = status
    }

    function finishPendingSceneApply() {
        if (applyAfterSceneCheck) {
            applyAfterSceneCheck = false
            commitApply()
        }
    }

    function finishSceneFallback(generation, item, reason, result, renderId) {
        if (!sceneRenderMatches(generation, item, renderId))
            return
        if (renderId)
            activeSceneRenderId = ""
        sceneChecking = false
        if (result && result.cancelled) {
            applyAfterSceneCheck = false
            applyBlocked = false
            selectedSourceReady = false
            sceneNeedsRestage = true
            applyStatus = "Scene preparation canceled • Previous wallpaper kept"
            return
        }
        sceneNeedsRestage = false
        if (result && result.ok) {
            var fallbackKind = result.kind === "video" ? "video" : "image"
            var fallbackPreview = result.preview || (fallbackKind === "image" ? result.path : item.preview.replace("file://", ""))
            stageSelectedSource(generation, item, fallbackKind, result.path, fallbackPreview)
            applyStatus = "Real scene ready • " + result.width + "×" + result.height
                    + (fallbackKind === "video" ? " animated fallback ready" : " still fallback ready")
            finishPendingSceneApply()
        } else {
            applyAfterSceneCheck = false
            applyBlocked = true
            selectedSourceReady = false
            applyStatus = "No safely prepared scene is available • Previous wallpaper kept"
        }
    }

    function renderStaticSceneFallback(generation, item, reason, assets) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return
        var renderId = nextSceneRenderId("static", generation, item)
        activeSceneRenderId = renderId
        sceneChecking = true
        applyStatus = "Checking for a safely prepared scene still…"
        var fallbackMode = cfg_MultiScreenMode === "span" ? "span" : "mirror"
        scenePreflightBridge.render_scene_fallback(
            item.folder, assets, fallbackMode, cfg_Scaling,
            runtimePropertyOverrides, cfg_DisableParallax, cfg_DisableParticles, renderId, true
        ).then(
            function(result) { root.finishSceneFallback(generation, item, reason, result, renderId) },
            function(error) { root.finishSceneFallback(generation, item, reason, {ok: false}, renderId) }
        )
    }

    function handleAnimatedSceneResult(generation, item, reason, assets, renderId, result) {
        if (!sceneRenderMatches(generation, item, renderId))
            return
        if (result && result.cancelled) {
            finishSceneFallback(generation, item, reason, result, renderId)
            return
        }
        if (result && result.ok) {
            finishSceneFallback(generation, item, reason, result, renderId)
            return
        }
        activeSceneRenderId = ""
        scenePreflightBridge.cancel_scene_render(renderId)
        renderStaticSceneFallback(generation, item, reason, assets)
    }

    function renderSceneFallback(generation, item, reason, assets) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return
        var renderId = nextSceneRenderId("animated", generation, item)
        activeSceneRenderId = renderId
        sceneChecking = true
        applyStatus = "Checking for a safely prepared animated scene…"
        var fallbackMode = cfg_MultiScreenMode === "span" ? "span" : "mirror"
        scenePreflightBridge.render_scene_video_fallback(
            item.folder, assets, fallbackMode, cfg_Scaling, cfg_Fps,
            runtimePropertyOverrides, cfg_DisableParallax, cfg_DisableParticles, renderId, true
        ).then(
            function(result) { root.handleAnimatedSceneResult(generation, item, reason, assets, renderId, result) },
            function(error) { root.handleAnimatedSceneResult(generation, item, reason, assets, renderId, {ok: false}) }
        )
    }

    function prepareNativeScene(generation, item) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return
        sceneChecking = true
        applyStatus = "Checking live scene safety…"
        var assets = cfg_SteamLibraryPath + "/steamapps/common/wallpaper_engine/assets"
        scenePreflightBridge.preflight_scene(item.media, assets).then(
            function(result) {
                if (generation !== root.selectionGeneration || !root.selectedItem || root.selectedItem.workshopId !== item.workshopId)
                    return
                if (result && result.safe) {
                    root.sceneChecking = false
                    root.sceneNeedsRestage = false
                    root.stageSelectedSource(generation, item, "scene", item.media, item.preview.replace("file://", ""))
                    root.applyStatus = "Live animated scene ready"
                    root.finishPendingSceneApply()
                } else {
                    root.renderSceneFallback(generation, item, result && result.status ? result.status : "native scene unavailable", assets)
                }
            },
            function(error) {
                if (generation === root.selectionGeneration)
                    root.renderSceneFallback(generation, item, "native scene preflight failed", assets)
            }
        )
    }

    function routeWallpaper(generation, item, info) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return
        if (item.kind === "scene") {
            prepareNativeScene(generation, item)
        } else {
            sceneChecking = false
            sceneNeedsRestage = false
            stageSelectedSource(generation, item, item.renderKind, item.media, item.preview.replace("file://", ""))
            applyStatus = item.support === "Unavailable" ? "No playable source" : "Ready to apply"
            finishPendingSceneApply()
        }
    }

    function selectionRequestMatches(generation, workshopId) {
        return generation === selectionGeneration
                && selectedItem
                && selectedItem.workshopId === workshopId
    }

    function loadInstalledOnlineItem(item, activate) {
        cancelActiveSceneRender()
        propertySaveTimer.stop()
        propertySaveGeneration += 1
        var requestGeneration = ++selectionGeneration
        stagedSelectionGeneration = -1
        stagedWorkshopId = ""
        selectedItem = item
        selectedSourceReady = false
        applyBlocked = false
        applyStatus = "Reading downloaded Wallpaper Engine project…"
        scenePreflightBridge.get_local_workshop_item(item.workshopId, cfg_WorkshopRoot).then(
            function(localItem) {
                if (!root.selectionRequestMatches(requestGeneration, item.workshopId))
                    return
                if (!localItem || !localItem.ok) {
                    root.applyStatus = "Steam download is not complete yet"
                    return
                }
                root.onlineAwaitingInstall = false
                workshopInstallTimer.stop()
                root.refreshLocalCatalog()
                root.chooseWallpaper(root.normalizedCatalogItem(localItem, false), activate)
            },
            function(error) {
                if (root.selectionRequestMatches(requestGeneration, item.workshopId))
                    root.applyStatus = "Could not inspect the downloaded wallpaper"
            }
        )
    }

    function selectGalleryItem(item, activate) {
        if (item.online) {
            if (item.installed) {
                loadInstalledOnlineItem(item, activate)
                return
            }
            cancelActiveSceneRender()
            propertySaveTimer.stop()
            propertySaveGeneration += 1
            selectionGeneration += 1
            stagedSelectionGeneration = -1
            stagedWorkshopId = ""
            applyAfterSceneCheck = false
            sceneChecking = false
            selectedSourceReady = false
            applyBlocked = false
            propertiesLoading = false
            wallpaperProperties = []
            visibleWallpaperProperties = []
            userPropertyOverrides = ({})
            presetPropertyOverrides = ({})
            runtimePropertyOverrides = ({})
            propertyCapabilityStatus = ""
            selectedItem = item
            if (compactLayout)
                inspectorCollapsed = false
            propertyStatus = "Install this item before its project properties can be read"
            applyStatus = "Not installed • Download in Dcent Workshop"
            if (activate)
                openWorkshopItemInPlugin(item.workshopId)
            return
        }
        chooseWallpaper(item, activate)
    }

    function activateGalleryItem(item) {
        if (selectedItem && selectedItem.workshopId === item.workshopId
                && selectedSourceReady && !propertiesLoading && !sceneChecking) {
            applyAfterSceneCheck = false
            applyNow()
            return
        }
        selectGalleryItem(item, true)
    }

    function openWorkshopItemInPlugin(workshopId) {
        var value = String(workshopId || "")
        if (!/^[0-9]{1,20}$/.test(value)) {
            onlineStatus = "Invalid Workshop item ID"
            return
        }
        onlineAwaitingInstall = true
        if (steamApiKeyConfigured) {
            onlineStatus = "Subscribing through Steam…"
            scenePreflightBridge.workshop_subscribe(value).then(
                function(result) {
                    if (!result || !result.subscribed) {
                        root.onlineAwaitingInstall = false
                        root.onlineStatus = result && result.error
                                ? result.error : "Could not subscribe through Steam"
                        return
                    }
                    root.onlineStatus = "Subscribed • Steam is downloading it in the background…"
                    workshopInstallTimer.start()
                },
                function(error) {
                    root.onlineAwaitingInstall = false
                    root.onlineStatus = "Could not subscribe through Steam"
                }
            )
            return
        }
        onlineStatus = "Downloading in the background…"
        scenePreflightBridge.workshop_download(value, cfg_SteamLibraryPath).then(
            function(result) {
                if (!result || !result.started) {
                    root.onlineAwaitingInstall = false
                    root.onlineStatus = result && result.error
                            ? result.error : "Could not start the background download"
                    return
                }
                workshopInstallTimer.start()
            },
            function(error) {
                root.onlineAwaitingInstall = false
                root.onlineStatus = "Could not start the background download"
            }
        )
    }

    function refreshSteamApiKeyStatus() {
        scenePreflightBridge.steam_api_key_status().then(
            function(result) {
                root.steamApiKeyConfigured = Boolean(result && result.configured)
            },
            function(error) {}
        )
    }

    function saveSteamApiKey() {
        var key = String(steamApiKeyField.text || "").trim()
        scenePreflightBridge.set_steam_api_key(key).then(
            function(result) {
                if (result && result.configured) {
                    root.steamApiKeyConfigured = true
                    root.steamApiKeyStatus = "Steam API key saved"
                    steamApiKeyField.text = ""
                } else {
                    root.steamApiKeyStatus = result && result.error ? result.error : "Invalid Steam API key"
                }
            },
            function(error) {
                root.steamApiKeyStatus = "Could not save the Steam API key"
            }
        )
    }

    function openSelectedWorkshopItem() {
        if (!selectedItem || !selectedItem.online)
            return
        openWorkshopItemInPlugin(selectedItem.workshopId)
    }

    function checkSelectedWorkshopInstall() {
        if (!selectedItem || !selectedItem.online) {
            workshopInstallTimer.stop()
            return
        }
        var workshopId = selectedItem.workshopId
        scenePreflightBridge.workshop_item_status(workshopId, cfg_WorkshopRoot).then(
            function(result) {
                if (!root.selectedItem || root.selectedItem.workshopId !== workshopId)
                    return
                if (result && result.installed)
                    root.loadInstalledOnlineItem(root.selectedItem)
                else
                    root.onlineStatus = "Waiting for Steam to finish downloading…"
            },
            function(error) { root.onlineStatus = "Could not check Steam download status" }
        )
    }

    function chooseWallpaper(item, activate) {
        cancelActiveSceneRender()
        propertySaveGeneration += 1
        var generation = ++selectionGeneration
        stagedSelectionGeneration = -1
        stagedWorkshopId = ""
        applyAfterSceneCheck = Boolean(activate)
        sceneChecking = false
        sceneNeedsRestage = item.kind === "scene"
        applyBlocked = false
        selectedSourceReady = false
        propertySaveTimer.stop()
        selectedItem = item
        if (compactLayout)
            inspectorCollapsed = false
        applyStatus = item.kind === "scene"
                ? "Ready to apply • real scene will be prepared on Apply"
                : "Reading project metadata…"
        loadWallpaperProject(generation, item, item.kind !== "scene")
    }

    function exportConfiguration() {
        var names = [
            "WallpaperPath", "PreviewPath", "MediaPath", "WorkshopRoot", "WallpaperType",
            "Scaling", "Muted", "Volume", "Fps", "DisableMouse", "SteamLibraryPath",
            "WallpaperWorkShopId", "WallpaperSource", "BackgroundColor", "DisplayMode",
            "Rotation", "PauseMode", "PauseFilterByScreen", "PauseOnBatPower",
            "PauseBatPercent", "VideoBackend", "MuteAudio", "MouseInput", "Speed",
            "DisableParallax", "DisableParticles", "PropertyOverrides",
            "MultiScreenMode", "VirtualDesktopX", "VirtualDesktopY",
            "VirtualDesktopWidth", "VirtualDesktopHeight"
        ]
        var result = {}
        for (var i = 0; i < names.length; ++i) {
            var propertyName = "cfg_" + names[i]
            if (root[propertyName] !== undefined)
                result[names[i]] = root[propertyName]
        }
        if (!kdeAllScreensEnabled) {
            result.MultiScreenMode = "single"
            result.VirtualDesktopX = 0
            result.VirtualDesktopY = 0
            result.VirtualDesktopWidth = 0
            result.VirtualDesktopHeight = 0
        } else if (result.MultiScreenMode === "single") {
            result.MultiScreenMode = "mirror"
        }
        return result
    }

    function syncAllScreens(configuration) {
        if (!kdeAllScreensEnabled) {
            applyStatus = "Enable KDE's Set for all screens to use Dcent multi-screen modes"
            return
        }
        configuration = configuration || exportConfiguration()
        var requestedWorkshopId = configuration.WallpaperWorkShopId
        scenePreflightBridge.apply_all_screens(configuration).then(
            function(result) {
                if (result && result.ok) {
                    root.appliedWorkshopId = requestedWorkshopId
                    root.applyStatus = configuration.MultiScreenMode === "span"
                            ? "Applied as one canvas across all screens" : "Applied to all screens"
                } else {
                    root.applyStatus = "Multi-screen apply failed"
                }
            },
            function(error) { root.applyStatus = "Multi-screen bridge failed" }
        )
    }

    function applyLoginPreview() {
        if (!selectedPreviewPath) {
            loginStatus = "Select a wallpaper with a preview first"
            return
        }
        loginApplying = true
        loginStatus = "Waiting for administrator authentication…"
        scenePreflightBridge.set_login_wallpaper(selectedPreviewPath).then(
            function(result) {
                root.loginApplying = false
                root.loginStatus = result && result.ok
                        ? "Login preview installed; visible at the next login"
                        : (result && result.error ? result.error : "Login preview was not installed")
            },
            function(error) {
                root.loginApplying = false
                root.loginStatus = "Login preview failed"
            }
        )
    }

    function forceLocalScreenMode() {
        cfg_MultiScreenMode = "single"
        cfg_VirtualDesktopX = 0
        cfg_VirtualDesktopY = 0
        cfg_VirtualDesktopWidth = 0
        cfg_VirtualDesktopHeight = 0
    }

    function screenTargetName(target) {
        if (target && typeof target.name !== "undefined")
            return String(target.name || "")
        if (typeof target === "string" || typeof target === "number")
            return String(target)
        return ""
    }

    function rememberScreenTarget(target) {
        var name = screenTargetName(target)
        if (name.length > 0 && name !== "null" && name !== "undefined")
            selectedScreenName = name
        return selectedScreenName
    }

    function selectedScreenTarget() {
        var target = screen
        if (!target && configDialog && typeof configDialog.selectedScreen !== "undefined")
            target = configDialog.selectedScreen
        return rememberScreenTarget(target)
    }

    function copyConfigurationToKde() {
        if (!wallpaperConfiguration) return
        var keys = wallpaperConfiguration.keys()
        for (var i = 0; i < keys.length; ++i) {
            var propertyName = "cfg_" + keys[i]
            if (root[propertyName] !== undefined)
                wallpaperConfiguration[keys[i]] = root[propertyName]
        }
    }

    function saveConfig() {
        if (!kdeAllScreensEnabled)
            forceLocalScreenMode()
        else if (cfg_MultiScreenMode === "single")
            cfg_MultiScreenMode = "mirror"
        copyConfigurationToKde()
    }

    function commitApply() {
        if (applyBlocked) {
            applyStatus = "Real wallpaper rendering failed • Nothing was applied"
            return
        }
        if (!selectedItem || !selectedSourceReady || !cfg_WallpaperSource) {
            applyStatus = "No playable source"
            return
        }
        if (stagedSelectionGeneration !== selectionGeneration
                || stagedWorkshopId !== selectedItem.workshopId
                || cfg_WallpaperWorkShopId !== selectedItem.workshopId) {
            applyStatus = "Selected wallpaper is not ready yet"
            return
        }

        var requestedGeneration = selectionGeneration
        var requestedWorkshopId = selectedItem.workshopId
        if (!kdeAllScreensEnabled) {
            forceLocalScreenMode()
            var screenConfiguration = exportConfiguration()
            copyConfigurationToKde()
            var targetName = selectedScreenTarget()
            if (configDialog && typeof configDialog.selectedScreen !== "undefined" && targetName.length > 0) {
                applyStatus = "Applying to selected screen…"
                scenePreflightBridge.apply_to_screen(screenConfiguration, targetName).then(
                    function(result) {
                        if (requestedGeneration !== root.selectionGeneration || requestedWorkshopId !== root.stagedWorkshopId)
                            return
                        if (result && result.ok) {
                            root.appliedWorkshopId = requestedWorkshopId
                            root.applyStatus = result.status || "Applied to selected screen"
                        } else {
                            root.applyStatus = result && result.status ? result.status : "Per-screen apply failed"
                        }
                    },
                    function(error) {
                        if (requestedGeneration === root.selectionGeneration)
                            root.applyStatus = "Per-screen apply bridge failed"
                    }
                )
            } else if (configDialog && typeof configDialog.applyWallpaper === "function") {
                configDialog.applyWallpaper()
                appliedWorkshopId = requestedWorkshopId
                applyStatus = "Applied to KDE's selected screen"
            } else {
                configurationChanged()
                applyStatus = "Ready — use KDE Apply for the selected screen"
            }
            return
        }

        var allScreensConfiguration = exportConfiguration()
        copyConfigurationToKde()
        applyStatus = "Applying to all screens…"
        syncAllScreens(allScreensConfiguration)
    }

    function applyNow() {
        if (propertiesLoading || sceneChecking) {
            applyAfterSceneCheck = true
            applyStatus = propertiesLoading
                    ? "Reading project metadata; Apply will continue automatically…"
                    : "Checking scene safety; Apply will continue automatically…"
            return
        }
        if (selectedItem && selectedItem.kind === "scene" && sceneNeedsRestage) {
            applyAfterSceneCheck = true
            sceneChecking = true
            selectedSourceReady = false
            routeWallpaper(selectionGeneration, selectedItem, {isPreset: Object.keys(presetPropertyOverrides).length > 0})
            return
        }
        commitApply()
    }

    onKdeAllScreensEnabledChanged: {
        if (kdeAllScreensEnabled && cfg_MultiScreenMode === "single") {
            cfg_MultiScreenMode = "mirror"
            configurationChanged()
        }
        if (selectedItem && selectedItem.kind === "scene")
            invalidateSceneRender("Screen target changed • Apply will rebuild the animated scene")
    }

    Component.onCompleted: {
        selectedScreenTarget()
        if (compactLayout)
            inspectorCollapsed = true
        appliedWorkshopId = cfg_WallpaperWorkShopId
        rebuildCatalog()
        refreshLocalCatalog()
        refreshSteamApiKeyStatus()
        if (kdeAllScreensEnabled && cfg_MultiScreenMode === "single")
            cfg_MultiScreenMode = "mirror"
        if (selectedItem) {
            applyStatus = "Currently applied • no unapplied changes"
            selectedSourceReady = cfg_WallpaperSource.length > 0
            applyBlocked = false
            var generation = ++selectionGeneration
            if (selectedSourceReady) {
                stagedSelectionGeneration = generation
                stagedWorkshopId = selectedItem.workshopId
            }
            loadWallpaperProject(generation, selectedItem, false)
        }
    }

    Component.onDestruction: cancelActiveSceneRender()

    ListModel { id: catalogModel }

    ColumnLayout {
        objectName: "libraryPane"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: root.compactLayout ? 0 : 560
        visible: !root.compactLayout || root.inspectorCollapsed
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading {
                text: "DcentWallpapers"
                level: 1
                Layout.fillWidth: true
            }
            Button {
                id: quickApplyButton
                objectName: "quickApplyButton"
                visible: root.inspectorCollapsed && root.selectedItem !== null
                text: root.selectedItem && root.selectedItem.workshopId === root.appliedWorkshopId
                      ? "Reapply" : "Apply selected"
                icon.name: "dialog-ok-apply"
                highlighted: true
                enabled: root.canApplySelection
                onClicked: root.applyNow()
                Accessible.onPressAction: root.applyNow()
            }
            ToolButton {
                id: inspectorToggle
                objectName: "inspectorToggle"
                text: root.inspectorCollapsed ? "Show details" : "Hide details"
                icon.name: root.inspectorCollapsed ? "sidebar-show-right" : "sidebar-collapse-right"
                display: AbstractButton.TextBesideIcon
                onClicked: root.inspectorCollapsed = !root.inspectorCollapsed
            }
        }
        Label {
            text: root.onlineMode
                  ? "Browse the live Wallpaper Engine Workshop, then download."
                  : "Your Wallpaper Engine library — ready for this desktop."
            color: root.textMuted
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TabBar {
                id: workshopSourcePicker
                objectName: "workshopSourcePicker"
                Layout.preferredWidth: 320
                currentIndex: root.onlineMode ? 1 : 0
                onCurrentIndexChanged: {
                    if ((currentIndex === 1) !== root.onlineMode)
                        root.switchCatalogMode(currentIndex === 1)
                }
                TabButton {
                    id: catalogLibraryTab
                    objectName: "catalogLibraryTab"
                    text: "Library"
                    icon.name: "view-list-icons"
                }
                TabButton {
                    id: catalogWorkshopTab
                    objectName: "catalogWorkshopTab"
                    text: "Workshop"
                    icon.name: "internet-services"
                }
            }
            ComboBox {
                id: workshopSortPicker
                objectName: "workshopSortPicker"
                visible: root.onlineMode
                Layout.fillWidth: true
                model: ["Trending", "Top rated", "Newest", "Most subscribed"]
                onActivated: root.performOnlineSearch(1)
            }
            BusyIndicator {
                running: root.onlineLoading
                visible: running
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: root.onlineMode
                        ? "Search Workshop wallpapers"
                        : "Search installed wallpapers"
                onTextChanged: {
                    if (root.onlineMode)
                        onlineSearchTimer.restart()
                    else
                        root.rebuildCatalog()
                }
            }
            ComboBox {
                id: typeFilter
                model: ["All", "scene", "video", "image", "web"]
                onCurrentTextChanged: {
                    if (root.onlineMode)
                        onlineSearchTimer.restart()
                    else
                        root.rebuildCatalog()
                }
            }
            Label {
                id: resultCount
                text: "0 installed"
                opacity: 0.7
                Layout.preferredWidth: 105
                horizontalAlignment: Text.AlignRight
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.onlineMode
            Button {
                id: workshopPreviousPage
                objectName: "workshopPreviousPage"
                text: "Previous"
                enabled: !root.onlineLoading && root.onlinePage > 1
                onClicked: root.performOnlineSearch(root.onlinePage - 1)
            }
            Label {
                Layout.fillWidth: true
                text: root.onlineStatus || ("Workshop page " + root.onlinePage)
                elide: Text.ElideRight
                opacity: 0.75
                horizontalAlignment: Text.AlignHCenter
            }
            Button {
                id: workshopNextPage
                objectName: "workshopNextPage"
                text: "Next"
                enabled: !root.onlineLoading && root.onlineHasMore
                onClicked: root.performOnlineSearch(root.onlinePage + 1)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: root.appSurface
            border.color: root.borderSubtle
            clip: true

            GridView {
                id: grid
                objectName: "wallpaperGrid"
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                readonly property int columnCount: Math.max(1, Math.round(width / 320))
                cellWidth: width / columnCount
                cellHeight: Math.round((cellWidth - 12) * 9 / 16) + 84
                model: catalogModel
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 900
                flickDeceleration: 3200
                maximumFlickVelocity: 24000
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    width: 12
                }
                WheelHandler {
                    onWheel: function(event) {
                        var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 3.0 : (event.angleDelta.y / 120.0) * grid.cellHeight * 3.0
                        var limit = Math.max(0, grid.contentHeight - grid.height)
                        grid.contentY = Math.max(0, Math.min(limit, grid.contentY - delta))
                        event.accepted = true
                    }
                }
                delegate: Rectangle {
                    required property string title
                    required property string workshopId
                    required property string kind
                    required property string renderKind
                    required property string support
                    required property string folder
                    required property string preview
                    required property string media
                    required property real sizeBytes
                    required property int previewWidth
                    required property int previewHeight
                    required property bool online
                    required property bool installed
                    required property string author
                    required property string authorUrl
                    required property string creator
                    required property string description
                    required property string tagsText
                    required property real updatedEpoch
                    required property real subscriptions
                    required property real views
                    required property real rating
                    required property string workshopUrl
                    readonly property bool selected: Boolean(root.selectedItem && root.selectedItem.workshopId === workshopId)
                    readonly property bool applied: workshopId === root.appliedWorkshopId

                    width: grid.cellWidth - 12
                    height: grid.cellHeight - 12
                    radius: 12
                    color: selected ? Kirigami.Theme.alternateBackgroundColor : (cardMouse.containsMouse ? Kirigami.Theme.hoverColor : root.cardSurface)
                    border.width: selected ? 2 : 1
                    border.color: selected ? root.steamBlue : root.borderSubtle
                    activeFocusOnTab: true
                    Accessible.name: title
                    Accessible.description: applied ? "Currently applied wallpaper" : (selected ? "Selected wallpaper" : kind + " wallpaper")
                    Accessible.role: Accessible.ListItem
                    Accessible.onPressAction: root.selectGalleryItem(itemRecord())
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.activateGalleryItem(itemRecord())
                            event.accepted = true
                        } else if (event.key === Qt.Key_Space) {
                            root.selectGalleryItem(itemRecord())
                            event.accepted = true
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Rectangle {
                            id: cardPreview
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.round((grid.cellWidth - 28) * 9 / 16)
                            radius: 8
                            color: Kirigami.Theme.backgroundColor
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: preview
                                asynchronous: true
                                retainWhileLoading: false
                                cache: true
                                smooth: true
                                fillMode: Image.PreserveAspectCrop
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 7
                                width: typeText.implicitWidth + 14
                                height: 24
                                radius: 12
                                color: Kirigami.Theme.highlightColor
                                Label {
                                    id: typeText
                                    anchors.centerIn: parent
                                    text: kind.toUpperCase()
                                    color: Kirigami.Theme.highlightedTextColor
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                            Rectangle {
                                visible: online
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 7
                                width: onlineStateText.implicitWidth + 14
                                height: 24
                                radius: 12
                                color: installed ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                                Label {
                                    id: onlineStateText
                                    anchors.centerIn: parent
                                    text: installed ? "INSTALLED" : "DOWNLOAD"
                                    color: Kirigami.Theme.backgroundColor
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: title
                            font.bold: true
                            font.pixelSize: 14
                            color: root.textPrimary
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            text: online
                                  ? ((author ? "By " + author + "  •  " : "") + (installed ? "Downloaded" : "Not installed"))
                                  : ((previewWidth > 0 ? previewWidth + "×" + previewHeight + "  •  " : "") + (sizeBytes / 1048576).toFixed(1) + " MB")
                            color: root.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 3
                        visible: parent.selected
                        color: root.steamBlueStrong
                        radius: 2
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 15
                        anchors.topMargin: 48
                        width: stateText.implicitWidth + 16
                        height: stateText.implicitHeight + 8
                        radius: height / 2
                        visible: applied || selected
                        color: applied ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.highlightColor
                        Label {
                            id: stateText
                            anchors.centerIn: parent
                            text: applied ? "Applied" : "Selected"
                            color: applied ? Kirigami.Theme.backgroundColor : Kirigami.Theme.highlightedTextColor
                            font.bold: true
                        }
                    }
                    function itemRecord() {
                        return {
                            title: title, workshopId: workshopId, kind: kind, renderKind: renderKind,
                            support: support, folder: folder, preview: preview, media: media,
                            sizeBytes: sizeBytes, previewWidth: previewWidth, previewHeight: previewHeight,
                            online: online, installed: installed, author: author, authorUrl: authorUrl,
                            creator: creator, description: description, tagsText: tagsText,
                            updatedEpoch: updatedEpoch, subscriptions: subscriptions, views: views,
                            rating: rating, workshopUrl: workshopUrl
                        }
                    }
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        cursorShape: Qt.PointingHandCursor
                        ToolTip.visible: containsMouse
                        ToolTip.text: title
                        ToolTip.delay: 600
                    }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onSingleTapped: root.selectGalleryItem(parent.itemRecord())
                        onDoubleTapped: root.activateGalleryItem(parent.itemRecord())
                    }
                }
            }
        }
    }

    Rectangle {
        objectName: "inspectorPanel"
        Layout.preferredWidth: root.compactLayout ? root.width : 420
        Layout.minimumWidth: root.compactLayout ? 0 : 400
        Layout.fillWidth: root.compactLayout
        Layout.fillHeight: true
        visible: !root.inspectorCollapsed
        color: Kirigami.Theme.backgroundColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            ScrollView {
                id: settingsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: 8

                ToolButton {
                    visible: root.compactLayout
                    text: "Back to library"
                    icon.name: "go-previous"
                    display: AbstractButton.TextBesideIcon
                    onClicked: root.inspectorCollapsed = true
                }
                Kirigami.Heading {
                    text: root.selectedItem ? root.selectedItem.title : "Wallpaper details"
                    level: 2
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    text: root.selectedItem ? (root.selectedItem.kind.toUpperCase() + "  •  Workshop " + root.selectedItem.workshopId) : "Select a wallpaper to inspect and customize"
                    color: root.textMuted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    id: selectionStateLabel
                    objectName: "selectionStateLabel"
                    visible: root.selectedItem !== null
                    text: root.selectedItem && root.selectedItem.workshopId === root.appliedWorkshopId
                          ? "Currently applied" : "Selected — not applied yet"
                    color: root.selectedItem && root.selectedItem.workshopId === root.appliedWorkshopId
                           ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                    font.bold: true
                    Layout.fillWidth: true
                }
                Label {
                    text: root.sceneChecking ? "● Preparing scene…" : (root.selectedItem ? "● " + root.selectedItem.support : "")
                    color: root.sceneChecking ? Kirigami.Theme.highlightColor
                           : (root.selectedItem && root.selectedItem.online && !root.selectedItem.installed ? Kirigami.Theme.neutralTextColor
                              : (root.selectedItem && root.selectedItem.support !== "Unavailable" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor))
                    font.bold: true
                    Layout.fillWidth: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: 10
                    color: root.appSurface
                    clip: true
                    Image {
                        id: selectedPreviewImage
                        objectName: "selectedPreviewImage"
                        anchors.fill: parent
                        anchors.margins: 3
                        source: root.selectedItem ? root.selectedItem.preview : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        retainWhileLoading: false
                        smooth: true
                    }
                    Column {
                        objectName: "selectedPreviewPlaceholder"
                        anchors.centerIn: parent
                        spacing: 8
                        visible: selectedPreviewImage.status === Image.Null || selectedPreviewImage.status === Image.Error
                        Kirigami.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 48
                            height: 48
                            source: root.selectedItem ? "image-x-generic" : "preferences-desktop-wallpaper"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.selectedItem ? "Preview unavailable" : "Select a wallpaper"
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }
                Kirigami.Heading {
                    objectName: "configureHeading"
                    Layout.fillWidth: true
                    text: "Configure"
                    level: 2
                }
                Kirigami.InlineMessage {
                    objectName: "overviewStateMessage"
                    Layout.fillWidth: true
                    visible: root.selectedItem !== null
                    type: root.selectedItem && root.selectedItem.workshopId === root.appliedWorkshopId
                          ? Kirigami.MessageType.Positive : Kirigami.MessageType.Information
                    text: root.selectedItem && root.selectedItem.workshopId === root.appliedWorkshopId
                          ? "This wallpaper is currently active on the selected screen."
                          : (root.selectedItem && root.selectedItem.online && !root.selectedItem.installed
                             ? "Download and finish before applying this wallpaper."
                             : "This wallpaper is selected and ready to apply.")
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: onlineInstallColumn.implicitHeight + 20
                    visible: Boolean(root.selectedItem && root.selectedItem.online && !root.selectedItem.installed)
                    radius: 10
                    color: Kirigami.Theme.alternateBackgroundColor
                    border.color: Kirigami.Theme.neutralTextColor
                    ColumnLayout {
                        id: onlineInstallColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 7
                        Label {
                            Layout.fillWidth: true
                            text: "Available from Steam Workshop"
                            font.bold: true
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.selectedItem && root.selectedItem.author
                                  ? "Created by " + root.selectedItem.author : "Not downloaded yet"
                            opacity: 0.75
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: Boolean(root.selectedItem && String(root.selectedItem.description || "").length > 0)
                            text: root.selectedItem ? String(root.selectedItem.description || "") : ""
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: Boolean(root.selectedItem && String(root.selectedItem.tagsText || "").length > 0)
                            text: root.selectedItem ? String(root.selectedItem.tagsText || "") : ""
                            color: root.steamBlue
                            wrapMode: Text.WordWrap
                            font.pixelSize: 11
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: root.selectedItem && (root.selectedItem.subscriptions > 0 || root.selectedItem.views > 0 || root.selectedItem.sizeBytes > 0)
                            text: root.selectedItem
                                  ? ((root.selectedItem.subscriptions > 0 ? root.selectedItem.subscriptions.toLocaleString(Qt.locale()) + " subscribers  •  " : "")
                                     + (root.selectedItem.views > 0 ? root.selectedItem.views.toLocaleString(Qt.locale()) + " views  •  " : "")
                                     + (root.selectedItem.sizeBytes > 0 ? (root.selectedItem.sizeBytes / 1048576).toFixed(1) + " MB" : ""))
                                  : ""
                            opacity: 0.72
                            wrapMode: Text.WordWrap
                            font.pixelSize: 11
                        }
                        Button {
                            Layout.fillWidth: true
                            text: root.onlineAwaitingInstall ? "DOWNLOADING…" : "DOWNLOAD"
                            enabled: !root.onlineAwaitingInstall
                            onClicked: root.openSelectedWorkshopItem()
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Check download now"
                            onClicked: root.checkSelectedWorkshopInstall()
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.onlineStatus
                            visible: text.length > 0
                            opacity: 0.7
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                ColumnLayout {
                    objectName: "wallpaperSettingsSection"
                    Layout.fillWidth: true
                    visible: Boolean(root.selectedItem && !(root.selectedItem.online && !root.selectedItem.installed))
                    spacing: 12
                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading {
                            text: "Wallpaper settings"
                            level: 3
                            Layout.fillWidth: true
                        }
                        Button {
                            text: "Reset"
                            enabled: !root.propertiesLoading && Object.keys(root.userPropertyOverrides).length > 0
                            onClicked: root.resetWallpaperProperties()
                        }
                    }
                Label {
                    Layout.fillWidth: true
                    text: root.selectedItem
                          ? "Settings stored separately for “" + root.selectedItem.title + "”."
                          : "Select a wallpaper to configure its own settings."
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: root.propertiesLoading ? "Reading project.json…" : root.propertyStatus
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    visible: root.propertyCapabilityStatus.length > 0
                    text: root.propertyCapabilityStatus
                    color: root.steamBlue
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }
                Label {
                    Layout.fillWidth: true
                    visible: root.selectedItem && root.selectedItem.kind === "scene" && Object.keys(root.runtimePropertyOverrides).length > 0
                    text: "This native scene library cannot apply arbitrary user constants safely. Dcent applies these values through the compatibility renderer and keeps the result animated in Plasma."
                    color: Kirigami.Theme.neutralTextColor
                    wrapMode: Text.WordWrap
                }
                TextField {
                    id: propertySearchField
                    Layout.fillWidth: true
                    visible: root.wallpaperProperties.length > 8
                    placeholderText: "Filter project properties"
                    onTextChanged: {
                        root.propertyQuery = text
                        root.refreshVisibleWallpaperProperties()
                    }
                }
                ListView {
                    id: wallpaperPropertyList
                    objectName: "wallpaperEnginePropertyList"
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? contentHeight : 0
                    visible: !root.propertiesLoading && count > 0
                    clip: true
                    spacing: 2
                    model: root.visibleWallpaperProperties
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool presentation: modelData.type === "group" || modelData.type === "label" || modelData.type === "text"
                        width: wallpaperPropertyList.width - 8
                        height: propertyEditorColumn.implicitHeight + 8
                        radius: 4
                        color: presentation ? "transparent" : Kirigami.Theme.alternateBackgroundColor
                        border.width: presentation ? 0 : 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: propertyEditorColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            spacing: 3

                            Label {
                                Layout.fillWidth: true
                                text: root.friendlyPropertyLabel(modelData)
                                font.bold: modelData.type === "group" || !presentation
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: Boolean(!presentation && modelData.description && modelData.description !== modelData.label)
                                text: modelData.description || ""
                                opacity: 0.65
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                            }
                            CheckBox {
                                visible: modelData.editable && modelData.type === "bool"
                                text: checked ? "Enabled" : "Disabled"
                                checked: Boolean(root.wallpaperPropertyValue(modelData.name, modelData.default))
                                onToggled: root.setWallpaperProperty(modelData.name, checked)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: modelData.editable && modelData.type === "slider"
                                RowLayout {
                                    Layout.fillWidth: true
                                    Slider {
                                        Layout.fillWidth: true
                                        from: Number(modelData.min)
                                        to: Number(modelData.max)
                                        stepSize: Number(modelData.step) > 0 ? Number(modelData.step) : 0
                                        value: Number(root.wallpaperPropertyValue(modelData.name, modelData.default))
                                        onMoved: root.setWallpaperProperty(modelData.name, value)
                                    }
                                    TextField {
                                        Layout.preferredWidth: 76
                                        visible: Boolean(modelData.allowTextEntry)
                                        horizontalAlignment: Text.AlignRight
                                        text: Number(root.wallpaperPropertyValue(modelData.name, modelData.default)).toFixed(Math.min(12, Number(modelData.precision || 0)))
                                        validator: DoubleValidator {
                                            bottom: Number(modelData.min)
                                            top: Number(modelData.max)
                                            decimals: 12
                                        }
                                        onEditingFinished: root.setWallpaperProperty(modelData.name, Number(text))
                                    }
                                }
                            }
                            ComboBox {
                                Layout.fillWidth: true
                                visible: modelData.editable && modelData.type === "combo"
                                model: root.comboPropertyOptions(modelData)
                                textRole: "label"
                                currentIndex: root.comboPropertyIndex(modelData)
                                onActivated: {
                                    if (currentIndex >= 0 && currentIndex < model.length)
                                        root.setWallpaperProperty(modelData.name, model[currentIndex].value)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: modelData.editable && modelData.type === "color"
                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 30
                                    radius: 5
                                    color: root.qmlColor(root.wallpaperPropertyValue(modelData.name, modelData.default))
                                    border.color: Kirigami.Theme.disabledTextColor
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: root.wallpaperColorDisplay(
                                            root.wallpaperPropertyValue(modelData.name, modelData.default),
                                            modelData.components)
                                    elide: Text.ElideRight
                                }
                                Button {
                                    text: "Choose"
                                    onClicked: root.openColorEditor(modelData)
                                }
                            }
                            TextField {
                                Layout.fillWidth: true
                                visible: modelData.editable && (modelData.type === "textinput" || modelData.type === "usershortcut" || modelData.type === "unknown")
                                text: String(root.wallpaperPropertyValue(modelData.name, modelData.default))
                                placeholderText: modelData.type === "usershortcut" ? "Shortcut" : "Value"
                                onEditingFinished: root.setWallpaperProperty(modelData.name, text)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: modelData.editable && (modelData.type === "file" || modelData.type === "directory" || modelData.type === "scenetexture")
                                ComboBox {
                                    objectName: "wallpaperAssetPicker"
                                    Layout.fillWidth: true
                                    visible: (modelData.assetOptions || []).length > 0
                                    model: modelData.assetOptions || []
                                    textRole: "label"
                                    currentIndex: root.assetPropertyIndex(modelData)
                                    onActivated: {
                                        if (currentIndex >= 0 && currentIndex < model.length)
                                            root.setWallpaperProperty(modelData.name, model[currentIndex].value)
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: modelData.editable && (modelData.type === "file" || modelData.type === "directory" || modelData.type === "scenetexture")
                                TextField {
                                    Layout.fillWidth: true
                                    text: String(root.wallpaperPropertyValue(modelData.name, modelData.default))
                                    onEditingFinished: root.setWallpaperProperty(modelData.name, text)
                                }
                                Button {
                                    text: "Browse"
                                    onClicked: root.openPropertyFile(modelData)
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: Boolean(modelData.condition) && !PropertyConditions.isSupported(modelData.condition)
                                text: "Complex Wallpaper Engine condition retained; shown without executing project code."
                                opacity: 0.6
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                }
                ColumnLayout {
                    objectName: "dcentGeneralSettingsSection"
                    Layout.fillWidth: true
                    visible: true
                    spacing: 12
                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }
                    Kirigami.Heading {
                        id: dcentSectionHeader
                        text: "DcentWallpapers settings"
                        level: 3
                    }
                Label {
                    Layout.fillWidth: true
                    text: "General rendering and desktop behavior shared by wallpapers."
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }
                ColumnLayout {
                    objectName: "steamAccountSection"
                    Layout.fillWidth: true
                    spacing: 6
                    Label {
                        text: "Steam account"
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.steamApiKeyConfigured
                              ? "Connected — DOWNLOAD subscribes your account and Steam downloads the wallpaper in the background, with no Steam window."
                              : "Add your Steam Web API key to subscribe and download wallpapers through your own Steam account, with no Steam window. Get a key at steamcommunity.com/dev/apikey."
                        opacity: 0.75
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextField {
                            id: steamApiKeyField
                            objectName: "steamApiKeyField"
                            Layout.fillWidth: true
                            placeholderText: root.steamApiKeyConfigured
                                             ? "Key saved — enter a new one to replace"
                                             : "Paste your Steam Web API key"
                            echoMode: TextInput.Password
                        }
                        Button {
                            text: "Save"
                            enabled: steamApiKeyField.text.length > 0
                            onClicked: root.saveSteamApiKey()
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: root.steamApiKeyStatus.length > 0
                        text: root.steamApiKeyStatus
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                    }
                }
                ColumnLayout {
                    id: multiScreenSection
                    objectName: "multiScreenSection"
                    property bool gateOpen: root.kdeAllScreensEnabled
                    Layout.fillWidth: true
                    visible: gateOpen
                    enabled: gateOpen
                    spacing: 8

                    Label {
                        text: "Multiple screens"
                        font.bold: true
                    }
                    ComboBox {
                        id: multiScreenModePicker
                        objectName: "multiScreenModePicker"
                        Layout.fillWidth: true
                        model: ["One wallpaper across all screens", "Same wallpaper on every screen"]
                        currentIndex: root.cfg_MultiScreenMode === "span" ? 0 : 1
                        onActivated: {
                            root.cfg_MultiScreenMode = currentIndex === 0 ? "span" : "mirror"
                            if (root.selectedItem && root.selectedItem.kind === "scene")
                                root.invalidateSceneRender("Screen mode changed • Apply will rebuild the animated scene")
                            root.configurationChanged()
                        }
                    }
                    Label {
                        text: root.cfg_MultiScreenMode === "span"
                              ? "Use both screens as one wide canvas. Each output shows its own portion of the same wallpaper."
                              : "Show the same complete wallpaper independently on both screens."
                        opacity: 0.65
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                Kirigami.Separator {
                    Layout.fillWidth: true
                }
                Label {
                    text: "Login screen"
                    font.bold: true
                }
                Label {
                    text: "Use the selected wallpaper's still preview through KDE's built-in login provider. Live scene, web, audio, and mouse processing stay disabled before login for stability."
                    opacity: 0.65
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Button {
                    Layout.fillWidth: true
                    text: root.loginApplying ? "Waiting for authentication…" : "Use safe preview on login screen"
                    enabled: !root.loginApplying && root.selectedPreviewPath.length > 0
                    onClicked: root.applyLoginPreview()
                }
                Label {
                    visible: root.loginStatus.length > 0
                    text: root.loginStatus
                    opacity: 0.76
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    text: "Background scaling"
                    font.bold: true
                }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["fill", "fit", "stretch"]
                    currentIndex: Math.max(0, model.indexOf(root.cfg_Scaling))
                    onActivated: {
                        root.cfg_Scaling = currentText
                        root.cfg_DisplayMode = currentText === "fit" ? 0 : (currentText === "fill" ? 1 : 2)
                        if (root.selectedItem && root.selectedItem.kind === "scene")
                            root.invalidateSceneRender("Scaling changed • Apply will rebuild the animated scene")
                        root.configurationChanged()
                    }
                }
                Label {
                    text: root.cfg_Scaling === "fill" ? "Fill screen and crop edges" : root.cfg_Scaling === "fit" ? "Show the entire wallpaper with letterboxing" : "Stretch to the full display"
                    opacity: 0.65
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "FPS"; Layout.fillWidth: true }
                    SpinBox {
                        from: 15
                        to: 240
                        value: root.cfg_Fps
                        onValueModified: {
                            root.cfg_Fps = value
                            if (root.selectedItem && root.selectedItem.kind === "scene")
                                root.invalidateSceneRender("Frame rate changed • Apply will rebuild the animated scene")
                            root.configurationChanged()
                        }
                    }
                }
                Label { text: "Volume " + root.cfg_Volume + "%" }
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: root.cfg_Volume
                    onMoved: {
                        root.cfg_Volume = Math.round(value)
                        root.cfg_Muted = root.cfg_Volume === 0
                        root.cfg_MuteAudio = root.cfg_Muted
                        root.configurationChanged()
                    }
                }
                CheckBox {
                    text: "Mute audio"
                    checked: root.cfg_Muted
                    onToggled: {
                        root.cfg_Muted = checked
                        root.cfg_MuteAudio = checked
                        root.configurationChanged()
                    }
                }
                CheckBox {
                    text: "System audio reactivity"
                    checked: root.cfg_SystemAudioCapture
                    onToggled: {
                        root.cfg_SystemAudioCapture = checked
                        root.configurationChanged()
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: "Let audio-responsive scene and web wallpapers react to the current PipeWire output."
                    opacity: 0.65
                    wrapMode: Text.WordWrap
                }
                CheckBox {
                    text: "Interactive wallpaper mode"
                    checked: root.cfg_MouseInput
                    onToggled: {
                        root.cfg_MouseInput = checked
                        root.cfg_DisableMouse = !checked
                        root.configurationChanged()
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: "Send desktop left-clicks, drags, and pointer movement to interactive web wallpapers. Turn this off when you need to select desktop icons."
                    opacity: 0.65
                    wrapMode: Text.WordWrap
                }
                CheckBox {
                    visible: root.selectedItem && root.selectedItem.kind === "scene"
                    text: "Disable scene parallax"
                    checked: root.cfg_DisableParallax
                    onToggled: {
                        root.cfg_DisableParallax = checked
                        root.invalidateSceneRender("Parallax setting changed • Apply will rebuild the animated scene")
                        root.configurationChanged()
                    }
                }
                CheckBox {
                    visible: root.selectedItem && root.selectedItem.kind === "scene"
                    text: "Disable scene particles"
                    checked: root.cfg_DisableParticles
                    onToggled: {
                        root.cfg_DisableParticles = checked
                        root.invalidateSceneRender("Particle setting changed • Apply will rebuild the animated scene")
                        root.configurationChanged()
                    }
                }
                Label { text: "Playback speed " + root.cfg_Speed.toFixed(2) + "×" }
                Slider {
                    Layout.fillWidth: true
                    from: 25
                    to: 200
                    stepSize: 5
                    value: root.cfg_Speed * 100
                    onMoved: {
                        root.cfg_Speed = value / 100
                        root.configurationChanged()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Rotation"; Layout.fillWidth: true }
                    ComboBox {
                        model: ["0°", "90°", "180°", "270°"]
                        currentIndex: Math.max(0, [0, 90, 180, 270].indexOf(root.cfg_Rotation))
                        onActivated: {
                            root.cfg_Rotation = [0, 90, 180, 270][currentIndex]
                            root.configurationChanged()
                        }
                    }
                }
                Label { text: "Pause behavior"; font.bold: true }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["Never pause", "Any window", "Maximized window", "Focused window", "Focused or maximized", "Fullscreen window"]
                    currentIndex: Math.max(0, root.cfg_PauseMode)
                    onActivated: {
                        root.cfg_PauseMode = currentIndex
                        root.configurationChanged()
                    }
                }
                Label { text: "Video renderer"; font.bold: true; visible: root.selectedItem && root.selectedItem.renderKind === "video" }
                ComboBox {
                    Layout.fillWidth: true
                    visible: root.selectedItem && root.selectedItem.renderKind === "video"
                    model: ["Qt Multimedia (recommended)", "MPV"]
                    currentIndex: root.cfg_VideoBackend
                    onActivated: {
                        root.cfg_VideoBackend = currentIndex
                        root.configurationChanged()
                    }
                }
                Label {
                    visible: root.selectedItem && root.selectedItem.kind === "scene"
                    text: "Scenes are rendered from the real Wallpaper Engine package into a cached full-resolution animated loop. The Workshop thumbnail is never used as the applied wallpaper."
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    Layout.fillWidth: true
                }
                }
                }
            }
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            Button {
                id: primaryApplyButton
                objectName: "primaryApplyButton"
                Layout.fillWidth: true
                text: !root.kdeAllScreensEnabled ? "Apply to selected screen"
                      : (root.sceneChecking ? "Apply when ready"
                         : (root.cfg_MultiScreenMode === "span" ? "Apply across all screens" : "Apply to all screens"))
                icon.name: "dialog-ok-apply"
                highlighted: true
                enabled: root.canApplySelection
                onClicked: root.applyNow()
                Accessible.onPressAction: root.applyNow()
            }
            Label {
                Layout.fillWidth: true
                text: root.applyStatus
                color: root.applyStatus.indexOf("Applied") === 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                opacity: root.applyStatus.indexOf("Applied") === 0 ? 1.0 : 0.7
                wrapMode: Text.WordWrap
            }
        }
    }
}
