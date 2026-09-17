pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as Dialogs
import org.kde.kirigami as Kirigami
import "../data/library.js" as LibraryData
import "PropertyConditions.js" as PropertyConditions

RowLayout {
    id: root
    objectName: "wallpaperConfigRoot"
    spacing: 8

    readonly property color steamBlue: Kirigami.Theme.highlightColor
    readonly property color steamBlueStrong: Kirigami.Theme.highlightColor
    readonly property color appSurface: Kirigami.Theme.backgroundColor
    readonly property color panelSurface: Kirigami.Theme.alternateBackgroundColor
    readonly property bool darkPalette: (appSurface.r + appSurface.g + appSurface.b) / 3 < 0.5
    readonly property color cardSurface: darkPalette ? Qt.rgba(0.025, 0.028, 0.035, 1) : Kirigami.Theme.alternateBackgroundColor
    readonly property color cardHover: darkPalette ? Qt.rgba(0.07, 0.075, 0.09, 1) : Kirigami.Theme.hoverColor
    readonly property color borderSubtle: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
    readonly property color textPrimary: Kirigami.Theme.textColor
    readonly property color textMuted: Kirigami.Theme.disabledTextColor
    property bool inspectorCollapsed: true
    property bool advancedExpanded: false
    onAdvancedExpandedChanged: {
        if (advancedExpanded)
            inspectorCollapsed = false
    }
    property bool wallpaperOptionsExpanded: true
    property bool filtersExpanded: false
    readonly property bool compactLayout: width < 980

    // Picker filters are intentionally UI-local. cfg_FilterStr belongs to the
    // runtime randomizer and must not be changed while merely browsing.
    property string filterQuery: ""
    property string filterType: "all"
    property string filterTag: "all tags"
    property string filterResolution: "any"
    property string filterRating: "all"
    property string filterInstallState: "all"
    property string sortMode: "name-asc"

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
    property bool cfg_RandomDownloadEnabled: false
    property int cfg_RandomDownloadDelayMinutes: 60
    property int cfg_RandomDownloadAgeLimit: 18
    property string cfg_RandomDownloadQuery: ""
    property string cfg_RandomDownloadKind: "all"
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
    onSelectedItemChanged: {
        if (selectedItem) {
            inspectorCollapsed = false
            Qt.callLater(initializeActiveSelection)
        }
    }
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
    property bool randomMode: false
    property bool onlineLoading: false
    property bool onlineAwaitingInstall: false
    // A requested item is applied only if that exact selection still owns the
    // request when Steam finishes. Switching cards never redirects the job.
    property bool pendingAutoApply: false
    property string pendingWorkshopId: ""
    property int pendingWorkshopSelectionGeneration: -1
    property int workshopInstallAttempts: 0
    property int onlinePage: 1
    property bool onlineHasMore: false
    property int onlineTotal: 0
    property int onlineSearchGeneration: 0
    property string onlineStatus: ""
    property var localCatalog: LibraryData.wallpapers
    property bool localCatalogRefreshing: false
    property int localCatalogGeneration: 0
    property var libraryTagOptions: ["All tags"]

    Pyext { id: scenePreflightBridge }
    property var transactionBridge: scenePreflightBridge

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
        id: sceneRestageTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (root.selectedItem && root.selectedItem.kind === "scene"
                    && root.sceneNeedsRestage && !root.propertiesLoading
                    && !root.sceneChecking && !root.activeSceneRenderId)
                root.prepareNativeScene(root.selectionGeneration, root.selectedItem)
        }
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

    Dialogs.FolderDialog {
        id: steamLibraryFolderDialog
        title: "Choose your Steam library folder"
        onAccepted: root.setSteamLibraryPath(selectedFolder.toLocalFile())
    }

    Dialogs.ColorDialog {
        id: propertyColorDialog
        title: "Choose Wallpaper Engine color"
        onAccepted: root.setWallpaperProperty(
            root.colorPropertyName,
            root.wallpaperColorString(selectedColor, root.colorComponentCount)
        )
    }

    function normalizedTagArray(item) {
        var source = item && item.tags !== undefined ? item.tags : (item ? item.tagsText : [])
        if (typeof source === "string")
            source = source.length ? source.split("•") : []
        if (!Array.isArray(source))
            return []
        var seen = ({})
        var result = []
        for (var index = 0; index < source.length; ++index) {
            var value = String(source[index] || "").trim()
            var key = value.toLowerCase()
            if (value && !seen[key]) {
                seen[key] = true
                result.push(value)
            }
        }
        return result
    }

    function normalizedResolutionKey(item) {
        var explicit = String(item && item.resolutionKey ? item.resolutionKey : "").toLowerCase().replace("×", "x").replace(/\s+/g, "")
        if (explicit)
            return explicit
        var tags = normalizedTagArray(item)
        for (var index = 0; index < tags.length; ++index) {
            var tag = tags[index].toLowerCase().replace("×", "x")
            if (tag.indexOf("dynamic resolution") >= 0)
                return "dynamic"
            var match = tag.match(/(\d{3,5})\s*x\s*(\d{3,5})/)
            if (match)
                return match[1] + "x" + match[2]
        }
        var width = Number(item && item.sourceWidth || 0)
        var height = Number(item && item.sourceHeight || 0)
        return width > 0 && height > 0 ? width + "x" + height : "unknown"
    }

    function normalizedContentRating(item) {
        var value = String(item && (item.contentRating || item.contentrating) || "").toLowerCase()
        if (value === "everyone" || value === "questionable" || value === "mature")
            return value
        var tags = normalizedTagArray(item)
        for (var index = 0; index < tags.length; ++index) {
            value = tags[index].toLowerCase()
            if (value === "everyone" || value === "questionable" || value === "mature")
                return value
        }
        return "unknown"
    }

    function normalizedCatalogItem(item, isOnline) {
        var tags = normalizedTagArray(item)
        return {
            title: String(item.title || ("Workshop " + item.workshopId)),
            workshopId: String(item.workshopId || ""),
            kind: String(item.kind || (isOnline ? "workshop" : "unknown")),
            renderKind: String(item.renderKind || ""),
            support: String(item.support || (item.installed ? "Installed" : "Available on Steam")),
            compatibilityFallback: Boolean(item.compatibilityFallback),
            animatedCompatibility: Boolean(item.animatedCompatibility),
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
            tags: tags,
            tagsText: tags.join(" • "),
            contentRating: normalizedContentRating(item),
            resolutionKey: normalizedResolutionKey(item),
            sourceWidth: Number(item.sourceWidth || 0),
            sourceHeight: Number(item.sourceHeight || 0),
            installState: String(item.installState || (item.installed ? "installed" : "remote")),
            origin: String(item.origin || (isOnline ? "workshop-remote" : "steam-installed")),
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
        if (!pendingWorkshopId) {
            onlineAwaitingInstall = false
            workshopInstallTimer.stop()
        }
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
        var kind = ["scene", "video", "web", "image"].indexOf(root.filterType) >= 0
                ? root.filterType : "all"
        var requiredTags = []
        if (root.filterTag !== "all tags")
            requiredTags.push(root.filterTag)
        if (root.filterRating !== "all")
            requiredTags.push(root.filterRating.charAt(0).toUpperCase() + root.filterRating.slice(1))
        if (root.filterResolution === "dynamic")
            requiredTags.push("Dynamic resolution")
        else if (/^[0-9]+x[0-9]+$/.test(root.filterResolution))
            requiredTags.push(root.filterResolution.replace("x", " x "))
        transactionBridge.search_workshop(
            root.filterQuery.trim(), page, onlineSortValue(), kind, cfg_WorkshopRoot, requiredTags
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
                for (var index = 0; index < items.length; ++index) {
                    var normalizedItem = root.normalizedCatalogItem(items[index], true)
                    if (root.catalogItemMatches(normalizedItem))
                        catalogModel.append(normalizedItem)
                }
                var clientOnlyFilter = root.filterInstallState !== "all"
                        || root.filterResolution === "other"
                root.onlineTotal = clientOnlyFilter ? catalogModel.count : Number(result.total || items.length)
                root.onlineHasMore = clientOnlyFilter ? false : Boolean(result.hasMore)
                root.onlineStatus = clientOnlyFilter
                        ? (catalogModel.count + " matches on this Workshop page")
                        : (result.status || (root.onlineTotal + " Workshop wallpapers"))
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

    function steamLibraryForWorkshopRoot(path) {
        var normalized = String(path || "").replace(/^file:\/\//, "").replace(/\/+$/, "")
        var marker = "/steamapps/"
        var markerIndex = normalized.indexOf(marker)
        return markerIndex >= 0 ? normalized.substring(0, markerIndex) : normalized
    }

    function workshopRootForSteamLibrary(path) {
        var normalized = String(path || "").replace(/^file:\/\//, "").replace(/\/+$/, "")
        if (!normalized)
            return ""
        var contentMarker = "/steamapps/workshop/content/431960"
        if (normalized.endsWith(contentMarker))
            return normalized
        return steamLibraryForWorkshopRoot(normalized) + contentMarker
    }

    function setSteamLibraryPath(path) {
        var library = steamLibraryForWorkshopRoot(path)
        var workshopRoot = workshopRootForSteamLibrary(path)
        if (!library || !workshopRoot)
            return
        cfg_SteamLibraryPath = library
        cfg_WorkshopRoot = workshopRoot
        configurationChanged()
        refreshLocalCatalog()
        rebuildCatalog()
    }

    function refreshLocalCatalog() {
        var generation = ++localCatalogGeneration
        var workshopRoot = cfg_WorkshopRoot
        localCatalogRefreshing = true
        transactionBridge.list_local_workshop_items(workshopRoot).then(
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

    function libraryTagList() {
        var seen = ({})
        var out = []
        for (var i = 0; i < localCatalog.length; ++i) {
            var tags = normalizedTagArray(localCatalog[i])
            for (var t = 0; t < tags.length; ++t) {
                var key = tags[t].toLowerCase()
                if (!seen[key] && key !== "everyone" && key !== "questionable" && key !== "mature") {
                    seen[key] = true
                    out.push(tags[t])
                }
            }
        }
        out.sort(function(a, b) { return a.localeCompare(b) })
        return out
    }

    readonly property var librarySortModes: [
        "name-asc", "name-desc", "updated", "largest", "smallest", "type", "id"
    ]

    function catalogMetadata(item) {
        var parts = []
        var kind = String(item && item.kind || "unknown")
        parts.push(kind.charAt(0).toUpperCase() + kind.slice(1))
        var bytes = Number(item && item.sizeBytes || 0)
        if (bytes > 0)
            parts.push(bytes < 1048576 ? "<1 MB" : (bytes / 1048576).toFixed(1) + " MB")
        return parts.join(" • ")
    }

    function wheelTravel(pixelDelta, angleDelta, viewportHeight) {
        if (Number(pixelDelta) !== 0)
            return Number(pixelDelta)
        return (Number(angleDelta) / 120.0) * 72
    }

    function compareText(left, right) {
        left = String(left || "").toLowerCase()
        right = String(right || "").toLowerCase()
        return left === right ? 0 : (left < right ? -1 : 1)
    }

    function compareCatalogItems(a, b) {
        switch (root.sortMode) {
        case "name-desc": return -compareText(a.title, b.title)
        case "updated": return (Number(b.updatedEpoch || 0) - Number(a.updatedEpoch || 0)) || compareText(a.title, b.title)
        case "largest": return (Number(b.sizeBytes || 0) - Number(a.sizeBytes || 0)) || compareText(a.title, b.title)
        case "smallest": return (Number(a.sizeBytes || 0) - Number(b.sizeBytes || 0)) || compareText(a.title, b.title)
        case "type": return compareText(a.kind, b.kind) || compareText(a.title, b.title)
        case "id": return compareText(String(a.workshopId || "").padStart(20, "0"), String(b.workshopId || "").padStart(20, "0"))
        default: return compareText(a.title, b.title)
        }
    }

    function hasExactTag(item, wantedTag) {
        wantedTag = String(wantedTag || "").toLowerCase()
        if (!wantedTag || wantedTag === "all tags")
            return true
        var tags = normalizedTagArray(item)
        for (var index = 0; index < tags.length; ++index) {
            if (tags[index].toLowerCase() === wantedTag)
                return true
        }
        return false
    }

    function catalogItemMatches(item) {
        var normalized = normalizedCatalogItem(item, Boolean(item.online))
        var query = root.filterQuery.trim().toLowerCase()
        var haystack = [normalized.title, normalized.workshopId, normalized.author,
                        normalized.creator, normalized.description, normalized.kind,
                        normalized.tagsText].join(" ").toLowerCase()
        var matchesText = !query || haystack.indexOf(query) >= 0
        var matchesType = root.filterType === "all" || normalized.kind.toLowerCase() === root.filterType
        var matchesTag = hasExactTag(normalized, root.filterTag)
        var matchesRating = root.filterRating === "all" || normalized.contentRating === root.filterRating
        var matchesInstall = root.filterInstallState === "all"
                || (root.filterInstallState === "installed" && normalized.installed)
                || (root.filterInstallState === "remote" && !normalized.installed)
        var matchesResolution = root.filterResolution === "any"
                || (root.filterResolution === "other" && (normalized.resolutionKey === "unknown" || normalized.resolutionKey === "other"))
                || normalized.resolutionKey === root.filterResolution
        var matchesRandom = !randomMode || hasExactTag(normalized, "Random download")
        return matchesText && matchesType && matchesTag && matchesRating
                && matchesInstall && matchesResolution && matchesRandom
    }

    function clearLibraryFilters() {
        root.filterQuery = ""
        root.filterType = "all"
        root.filterTag = "all tags"
        root.filterResolution = "any"
        root.filterRating = "all"
        root.filterInstallState = "all"
        searchField.text = ""
        typeFilter.currentIndex = 0
        resolutionFilter.currentIndex = 0
        ratingFilter.currentIndex = 0
        installStateFilter.currentIndex = 0
        tagFilter.currentIndex = 0
        rebuildCatalog()
    }

    function rebuildCatalog() {
        if (onlineMode) {
            onlineSearchTimer.restart()
            return
        }
        catalogModel.clear()
        var matches = []
        for (var i = 0; i < localCatalog.length; ++i) {
            var item = localCatalog[i]
            if (catalogItemMatches(item))
                matches.push(item)
            if (!selectedItem && (String(item.workshopId || "") === cfg_WallpaperWorkShopId
                    || (!cfg_WallpaperWorkShopId && pathBelongsToItem(cfg_WallpaperPath, item.folder))))
                selectedItem = normalizedCatalogItem(item, false)
        }
        matches.sort(compareCatalogItems)
        for (var m = 0; m < matches.length; ++m)
            catalogModel.append(normalizedCatalogItem(matches[m], false))
        updateLibraryTagOptions()
    }

    function updateLibraryTagOptions() {
        var previousValue = root.filterTag
        var options = ["All tags"].concat(libraryTagList())
        libraryTagOptions = options
        var nextIndex = 0
        for (var index = 0; index < options.length; ++index) {
            if (options[index].toLowerCase() === previousValue.toLowerCase()) {
                nextIndex = index
                break
            }
        }
        tagFilter.currentIndex = nextIndex
        root.filterTag = String(options[nextIndex]).toLowerCase()
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
        if (sceneNeedsRestage && selectedItem && selectedItem.kind === "scene"
                && !sceneChecking && !activeSceneRenderId)
            sceneRestageTimer.restart()
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
        transactionBridge.write_wallpaper_properties(item.workshopId, item.folder, userPropertyOverrides).then(
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
        var activeLiveScene = item.workshopId === appliedWorkshopId && cfg_WallpaperSource.endsWith("+scene")
        if (item.kind === "scene" && !activeLiveScene)
            invalidateSceneRender("Resetting scene properties…")
        var generation = ++propertySaveGeneration
        propertyStatus = "Resetting properties…"
        transactionBridge.reset_wallpaper_properties(item.workshopId, item.folder).then(
            function(info) {
                if (generation !== root.propertySaveGeneration || !root.selectedItem || root.selectedItem.workshopId !== item.workshopId)
                    return
                root.applyProjectInfo(info || {}, "Project defaults restored")
                root.sceneNeedsRestage = item.kind === "scene" && !activeLiveScene
                root.cfg_PropertyOverrides = ""
                root.cfg_PerOptChanged = !root.cfg_PerOptChanged
                if (activeLiveScene)
                    root.settingsEdited()
                else
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
        var readableLabel = label.length > 1 || /[A-Za-z0-9]/.test(label)
        if (readableLabel && label !== name && label.indexOf("_") < 0)
            return label
        var cleaned = ((readableLabel ? label : "") || name)
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
        if (transactionBridge && typeof transactionBridge.cancel_scene_render === "function")
            transactionBridge.cancel_scene_render(renderId)
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
            sceneRestageTimer.restart()
        }
        if (status)
            applyStatus = status
    }

    function finishPendingSceneApply() {
        applyAfterSceneCheck = false
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
            applyStatus = "Ready — real scene rendered at " + result.width + "×" + result.height
                    + (fallbackKind === "video" ? " with animation" : " as a still") + " • Use KDE Apply"
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
        transactionBridge.render_scene_fallback(
            item.folder, assets, fallbackMode, cfg_Scaling,
            runtimePropertyOverrides, cfg_DisableParallax, cfg_DisableParticles, renderId, false
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
        transactionBridge.cancel_scene_render(renderId)
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
        transactionBridge.render_scene_video_fallback(
            item.folder, assets, fallbackMode, cfg_Scaling, cfg_Fps, 24,
            runtimePropertyOverrides, cfg_DisableParallax, cfg_DisableParticles, renderId, false
        ).then(
            function(result) { root.handleAnimatedSceneResult(generation, item, reason, assets, renderId, result) },
            function(error) { root.handleAnimatedSceneResult(generation, item, reason, assets, renderId, {ok: false}) }
        )
    }

    function prepareNativeScene(generation, item) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return
        if (sceneChecking || activeSceneRenderId)
            return
        sceneChecking = true
        var renderId = nextSceneRenderId("native", generation, item)
        activeSceneRenderId = renderId
        applyStatus = "Checking live scene safety…"
        var assets = cfg_SteamLibraryPath + "/steamapps/common/wallpaper_engine/assets"
        transactionBridge.preflight_scene(item.media, assets).then(
            function(result) {
                if (!root.sceneRenderMatches(generation, item, renderId))
                    return
                root.activeSceneRenderId = ""
                if (result && result.safe) {
                    root.sceneChecking = false
                    root.sceneNeedsRestage = false
                    root.stageSelectedSource(generation, item, "scene", item.media, item.preview.replace("file://", ""))
                    root.applyStatus = "Ready — live animated scene passed safety checks • Use KDE Apply"
                    root.finishPendingSceneApply()
                } else {
                    root.renderSceneFallback(generation, item, result && result.status ? result.status : "native scene unavailable", assets)
                }
            },
            function(error) {
                if (root.sceneRenderMatches(generation, item, renderId)) {
                    root.activeSceneRenderId = ""
                    root.renderSceneFallback(generation, item, "native scene preflight failed", assets)
                }
            }
        )
    }

    function routeWallpaper(generation, item, info) {
        if (generation !== selectionGeneration || !selectedItem || selectedItem.workshopId !== item.workshopId)
            return
        if (item.compatibilityFallback && item.animatedCompatibility) {
            cfg_DisableParallax = true
            cfg_DisableParticles = true
            renderSceneFallback(generation, item, "uses the verified animated compatibility renderer", cfg_SteamLibraryPath + "/steamapps/common/wallpaper_engine/assets")
            return
        }
        if (item.compatibilityFallback) {
            var fallbackPreview = String(item.preview || "").replace("file://", "")
            if (!fallbackPreview) {
                applyBlocked = true
                selectedSourceReady = false
                applyStatus = "Legacy canvas project has no safe preview fallback"
                return
            }
            sceneChecking = false
            sceneNeedsRestage = false
            stageSelectedSource(generation, item, "image", fallbackPreview, fallbackPreview)
            applyStatus = "Legacy canvas project • static compatibility fallback (no WebGL or audio)"
            finishPendingSceneApply()
        } else if (item.kind === "scene") {
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
        transactionBridge.get_local_workshop_item(item.workshopId, cfg_WorkshopRoot).then(
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
            applyStatus = "Subscribe or download this Workshop item before applying"
            if (activate)
                openWorkshopItemInPlugin(item.workshopId)
            return
        }
        chooseWallpaper(item, activate)
    }

    function activateGalleryItem(item) {
        // The KDE host owns Apply. Double click is a fast selection/details
        // gesture only; it must never bypass scene validation or output scope.
        selectGalleryItem(item, false)
    }

    function openWorkshopItemInPlugin(workshopId) {
        var value = String(workshopId || "")
        if (!/^[0-9]{1,20}$/.test(value)) {
            onlineStatus = "Invalid Workshop item ID"
            return
        }
        onlineAwaitingInstall = true
        pendingAutoApply = true
        pendingWorkshopId = value
        pendingWorkshopSelectionGeneration = selectionGeneration
        workshopInstallAttempts = 0
        var requestGeneration = selectionGeneration
        onlineStatus = "Downloading through your signed-in Steam client…"
        transactionBridge.workshop_download(value, cfg_SteamLibraryPath).then(
            function(result) {
                if (root.pendingWorkshopId !== value
                        || root.pendingWorkshopSelectionGeneration !== requestGeneration)
                    return
                if (!result || !result.started) {
                    root.onlineAwaitingInstall = false
                    root.pendingAutoApply = false
                    root.pendingWorkshopId = ""
                    root.pendingWorkshopSelectionGeneration = -1
                    root.onlineStatus = result && result.error
                            ? result.error : "Could not start the background download"
                    return
                }
                workshopInstallTimer.start()
            },
            function(error) {
                if (root.pendingWorkshopId !== value
                        || root.pendingWorkshopSelectionGeneration !== requestGeneration)
                    return
                root.onlineAwaitingInstall = false
                root.pendingAutoApply = false
                root.pendingWorkshopId = ""
                root.pendingWorkshopSelectionGeneration = -1
                root.onlineStatus = "Could not start the background download"
            }
        )
    }

    function openSelectedWorkshopItem() {
        if (!selectedItem || !selectedItem.online)
            return
        openWorkshopItemInPlugin(selectedItem.workshopId)
    }

    function checkSelectedWorkshopInstall() {
        var workshopId = pendingWorkshopId
        var requestGeneration = pendingWorkshopSelectionGeneration
        if (!workshopId) {
            workshopInstallTimer.stop()
            return
        }
        if (workshopInstallAttempts++ > 150) {
            // Steam can leave an item queued for a long time (paused downloads,
            // no connection). Stop waiting and say what to do instead of
            // polling forever behind a "downloading" status.
            workshopInstallTimer.stop()
            onlineAwaitingInstall = false
            pendingAutoApply = false
            pendingWorkshopId = ""
            pendingWorkshopSelectionGeneration = -1
            onlineStatus = "Steam has not finished this download yet • check the Steam client"
            return
        }
        transactionBridge.workshop_item_status(workshopId, cfg_WorkshopRoot).then(
            function(result) {
                if (root.pendingWorkshopId !== workshopId
                        || root.pendingWorkshopSelectionGeneration !== requestGeneration)
                    return
                if (result && result.installed) {
                    workshopInstallTimer.stop()
                    root.onlineAwaitingInstall = false
                    var applicable = result.applicable === undefined ? true : result.applicable
                    var stillOwned = root.pendingAutoApply
                            && root.selectionGeneration === requestGeneration
                            && root.selectedItem
                            && root.selectedItem.workshopId === workshopId
                    root.pendingAutoApply = false
                    root.pendingWorkshopId = ""
                    root.pendingWorkshopSelectionGeneration = -1
                    root.refreshLocalCatalog()
                    if (!applicable) {
                        // Dependency assets and unsupported projects download
                        // fine but cannot be applied as a wallpaper: report that
                        // instead of starting a render that cannot succeed.
                        root.selectedSourceReady = false
                        root.applyStatus = ""
                        root.onlineStatus = "Downloaded • this is a Workshop asset, not a standalone wallpaper"
                        return
                    }
                    if (stillOwned) {
                        root.onlineStatus = "Downloaded • preparing the selected wallpaper…"
                        root.loadInstalledOnlineItem(root.selectedItem, false)
                    } else {
                        root.onlineStatus = "Workshop download finished • available in Library"
                    }
                } else {
                    root.onlineStatus = "Waiting for Steam to finish downloading…"
                }
            },
            function(error) {
                if (root.pendingWorkshopId === workshopId
                        && root.pendingWorkshopSelectionGeneration === requestGeneration)
                    root.onlineStatus = "Could not check Steam download status"
            }
        )
    }

    function chooseWallpaper(item, activate) {
        cancelActiveSceneRender()
        propertySaveGeneration += 1
        var generation = ++selectionGeneration
        stagedSelectionGeneration = -1
        stagedWorkshopId = ""
        applyAfterSceneCheck = false
        sceneChecking = false
        sceneNeedsRestage = item.kind === "scene"
        applyBlocked = false
        selectedSourceReady = false
        propertySaveTimer.stop()
        selectedItem = item
        inspectorCollapsed = false
        applyStatus = item.kind === "scene"
                ? "Preparing the real animated scene…"
                : "Reading project metadata…"
        loadWallpaperProject(generation, item, true)
        // Keep the last verified cfg_* source while asynchronous preparation
        // runs; KDE Apply only publishes a fully staged source.
        configurationChanged()
    }

    property var pendingLiveSettings: null
    Timer {
        id: liveSettingsTimer
        interval: 250
        repeat: false
        onTriggered: root.flushLiveSettings()
    }

    function settingsEdited() {
        configurationChanged()
        if (!selectedItem || !appliedWorkshopId || selectedItem.workshopId !== appliedWorkshopId)
            return
        pendingLiveSettings = {
            generation: selectionGeneration,
            id: selectedItem.workshopId,
            folder: selectedItem.folder,
            target: selectedScreenTarget(),
            all: kdeAllScreensEnabled
        }
        liveSettingsTimer.restart()
    }

    function flushLiveSettings() {
        var request = pendingLiveSettings
        pendingLiveSettings = null
        if (!request || request.generation !== selectionGeneration || !selectedItem
                || request.id !== selectedItem.workshopId || request.target !== selectedScreenTarget()
                || request.all !== kdeAllScreensEnabled || (!request.all && !request.target))
            return
        var settings = exportConfiguration()
        if (!propertiesLoading)
            settings.PropertyOverrides = Object.keys(runtimePropertyOverrides).length
                    ? JSON.stringify(runtimePropertyOverrides) : ""
        transactionBridge.update_active_settings(settings, request.id, request.folder,
                request.target, request.all).then(function(result) {
            if (request.generation === root.selectionGeneration && result && result.ok)
                root.applyStatus = "Settings updated on active wallpaper"
        }, function() {
            if (request.generation === root.selectionGeneration)
                root.applyStatus = "Live settings update failed; use KDE Apply"
        })
    }

    function exportConfiguration() {
        var names = [
            "WallpaperPath", "PreviewPath", "MediaPath", "WorkshopRoot", "WallpaperType",
            "Scaling", "Muted", "Volume", "Fps", "DisableMouse", "SteamLibraryPath",
            "WallpaperWorkShopId", "WallpaperSource", "BackgroundColor", "DisplayMode",
            "Rotation", "PauseMode", "PauseFilterByScreen", "PauseOnBatPower",
            "PauseBatPercent", "VideoBackend", "MuteAudio", "MouseInput", "Speed", "SystemAudioCapture",
            "RandomDownloadEnabled", "RandomDownloadDelayMinutes", "RandomDownloadAgeLimit",
            "RandomDownloadQuery", "RandomDownloadKind",
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
        } else {
            if (result.MultiScreenMode === "single")
                result.MultiScreenMode = "mirror"
            // Mirrored/spanned wallpapers use one normal orientation on every
            // output. Per-screen rotation is not meaningful here and stale KCM
            // state previously turned all outputs sideways.
            result.Rotation = 0
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
        transactionBridge.apply_all_screens(configuration).then(
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
        transactionBridge.set_login_wallpaper(selectedPreviewPath).then(
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
        if (name.length > 0 && name !== "null" && name !== "undefined") {
            if (selectedScreenName && name !== selectedScreenName) {
                applyAfterSceneCheck = false
                if (selectedItem && selectedItem.kind === "scene")
                    invalidateSceneRender("Screen changed — press KDE Apply when ready")
            }
            selectedScreenName = name
        }
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
        else {
            if (cfg_MultiScreenMode === "single")
                cfg_MultiScreenMode = "mirror"
            cfg_Rotation = 0
        }
        if (selectedItem && (!selectedSourceReady
                || stagedSelectionGeneration !== selectionGeneration
                || stagedWorkshopId !== selectedItem.workshopId)) {
            applyStatus = sceneChecking || propertiesLoading
                    ? "Still preparing this wallpaper — press KDE Apply when Ready"
                    : "Selected wallpaper is not ready — previous wallpaper kept"
            configurationChanged()
            return
        }
        copyConfigurationToKde()
        var generation = selectionGeneration
        var workshopId = selectedItem ? selectedItem.workshopId : cfg_WallpaperWorkShopId
        Qt.callLater(function() {
            if (generation === root.selectionGeneration) {
                root.appliedWorkshopId = workshopId
                root.applyStatus = "Applied by KDE"
            }
        })
    }

    onKdeAllScreensEnabledChanged: {
        if (kdeAllScreensEnabled) {
            if (cfg_MultiScreenMode === "single")
                cfg_MultiScreenMode = "mirror"
            cfg_Rotation = 0
            configurationChanged()
        }
        if (selectedItem && selectedItem.kind === "scene")
            invalidateSceneRender("Screen target changed • Apply will rebuild the animated scene")
    }

    onCfg_WallpaperWorkShopIdChanged: Qt.callLater(initializeActiveSelection)

    function initializeActiveSelection() {
        if (selectionGeneration !== 0 || !cfg_WallpaperWorkShopId)
            return
        appliedWorkshopId = cfg_WallpaperWorkShopId
        if (!selectedItem || selectedItem.workshopId !== cfg_WallpaperWorkShopId)
            return
        applyStatus = "Active wallpaper"
        selectedSourceReady = cfg_WallpaperSource.length > 0
        applyBlocked = false
        var generation = ++selectionGeneration
        if (selectedSourceReady) {
            stagedSelectionGeneration = generation
            stagedWorkshopId = selectedItem.workshopId
        }
        loadWallpaperProject(generation, selectedItem, false)
    }

    Component.onCompleted: {
        selectedScreenTarget()
        if (compactLayout)
            inspectorCollapsed = true
        rebuildCatalog()
        refreshLocalCatalog()
        if (kdeAllScreensEnabled && cfg_MultiScreenMode === "single")
            cfg_MultiScreenMode = "mirror"
        Qt.callLater(initializeActiveSelection)
    }

    Component.onDestruction: cancelActiveSceneRender()

    ListModel { id: catalogModel }

    ColumnLayout {
        objectName: "libraryPane"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: root.compactLayout ? 0 : 560
        visible: !root.compactLayout || root.inspectorCollapsed
        spacing: 8

        RowLayout {
            id: galleryToolbar
            objectName: "galleryToolbar"
            Layout.fillWidth: true
            spacing: 6

            TabBar {
                id: workshopSourcePicker
                objectName: "workshopSourcePicker"
                Layout.preferredWidth: 300
                currentIndex: root.onlineMode ? 1 : (root.randomMode ? 2 : 0)
                onCurrentIndexChanged: {
                    root.onlineSearchGeneration += 1
                    root.onlineLoading = false
                    root.onlineMode = currentIndex === 1
                    root.randomMode = currentIndex === 2
                    if (root.onlineMode)
                        root.performOnlineSearch(1)
                    else {
                        if (root.randomMode)
                            root.refreshLocalCatalog()
                        root.rebuildCatalog()
                    }
                }
                TabButton { objectName: "catalogLibraryTab"; text: "Library"; icon.name: "view-grid" }
                TabButton { objectName: "catalogWorkshopTab"; text: "Workshop"; icon.name: "internet-services" }
                TabButton { objectName: "catalogRandomTab"; text: "Random"; icon.name: "media-playlist-shuffle" }
            }
            TextField {
                id: searchField
                objectName: "librarySearchField"
                Layout.fillWidth: true
                placeholderText: root.onlineMode ? "Search Workshop" : "Search library"
                onTextChanged: {
                    root.filterQuery = text
                    if (root.onlineMode)
                        onlineSearchTimer.restart()
                    else
                        root.rebuildCatalog()
                }
            }
            ToolButton {
                id: libraryFilterToggle
                objectName: "libraryFilterToggle"
                text: "Filters"
                icon.name: "view-filter"
                checkable: true
                checked: root.filtersExpanded
                display: AbstractButton.TextBesideIcon
                onClicked: root.filtersExpanded = checked
            }
            ComboBox {
                id: librarySortPicker
                objectName: "librarySortPicker"
                visible: !root.onlineMode
                Layout.preferredWidth: 150
                model: ["Name A–Z", "Name Z–A", "Updated", "Largest", "Smallest", "Type", "Workshop ID"]
                onActivated: {
                    root.sortMode = root.librarySortModes[currentIndex] || "name-asc"
                    root.rebuildCatalog()
                }
                ToolTip.visible: hovered
                ToolTip.text: "Sort installed wallpapers"
            }
            ComboBox {
                id: workshopSortPicker
                objectName: "workshopSortPicker"
                visible: root.onlineMode
                Layout.preferredWidth: 150
                model: ["Trending", "Top rated", "Newest", "Most subscribed"]
                onActivated: root.performOnlineSearch(1)
            }
            BusyIndicator {
                running: root.onlineLoading || root.localCatalogRefreshing
                visible: running
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
            }
            ToolButton {
                id: inspectorToggle
                objectName: "inspectorToggle"
                icon.name: root.inspectorCollapsed ? "sidebar-show-right" : "sidebar-collapse-right"
                text: root.inspectorCollapsed ? "Details" : "Hide"
                display: AbstractButton.IconOnly
                ToolTip.visible: hovered
                ToolTip.text: root.inspectorCollapsed ? "Show wallpaper details" : "Hide wallpaper details"
                onClicked: root.inspectorCollapsed = !root.inspectorCollapsed
            }
        }

        Flow {
            id: libraryFilterBar
            objectName: "libraryFilterBar"
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            visible: root.filtersExpanded
            spacing: 6

            ComboBox {
                id: typeFilter
                objectName: "libraryTypeFilter"
                width: 112
                model: ["All types", "Scene", "Video", "Image", "Web"]
                onActivated: {
                    root.filterType = currentIndex === 0 ? "all" : currentText.toLowerCase()
                    if (root.onlineMode) root.performOnlineSearch(1); else root.rebuildCatalog()
                }
            }
            ComboBox {
                id: tagFilter
                objectName: "libraryTagFilter"
                width: 170
                model: root.onlineMode
                       ? ["All tags", "Abstract", "Animal", "Anime", "Cartoon", "CGI", "Cyberpunk", "Fantasy", "Game", "Girls", "Guys", "Landscape", "Medieval", "Memes", "MMD", "Music", "Nature", "Pixel art", "Relaxing", "Retro", "Sci-Fi", "Sports", "Technology", "Television", "Vehicle", "Audio responsive", "Customizable", "Interactive"]
                       : root.libraryTagOptions
                onActivated: {
                    root.filterTag = currentText.toLowerCase()
                    if (root.onlineMode) root.performOnlineSearch(1); else root.rebuildCatalog()
                }
            }
            ComboBox {
                id: resolutionFilter
                objectName: "libraryResolutionFilter"
                width: 164
                model: ["Any resolution", "1920×1080", "2560×1440", "3840×2160", "1920×3840", "Dynamic", "Other / unknown"]
                onActivated: {
                    root.filterResolution = ["any", "1920x1080", "2560x1440", "3840x2160", "1920x3840", "dynamic", "other"][currentIndex]
                    if (root.onlineMode) root.performOnlineSearch(1); else root.rebuildCatalog()
                }
            }
            ComboBox {
                id: ratingFilter
                objectName: "libraryRatingFilter"
                width: 132
                model: ["Any rating", "Everyone", "Questionable", "Mature", "Unknown"]
                onActivated: {
                    root.filterRating = currentIndex === 0 ? "all" : currentText.toLowerCase()
                    if (root.onlineMode) root.performOnlineSearch(1); else root.rebuildCatalog()
                }
            }
            ComboBox {
                id: installStateFilter
                objectName: "libraryInstallStateFilter"
                width: 126
                visible: root.onlineMode
                model: ["All items", "Installed", "Not installed"]
                onActivated: {
                    root.filterInstallState = ["all", "installed", "remote"][currentIndex]
                    root.performOnlineSearch(1)
                }
            }
            Button {
                id: clearLibraryFiltersButton
                objectName: "clearLibraryFiltersButton"
                text: "Clear"
                flat: true
                onClicked: root.clearLibraryFilters()
            }
            Label {
                id: resultCount
                objectName: "libraryResultCount"
                text: root.onlineMode ? (catalogModel.count + " shown • " + root.onlineTotal.toLocaleString(Qt.locale()) + " online")
                                      : (catalogModel.count + " wallpapers")
                color: root.textMuted
                verticalAlignment: Text.AlignVCenter
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.onlineMode
            spacing: 6
            ToolButton {
                id: workshopPreviousPage
                objectName: "workshopPreviousPage"
                icon.name: "go-previous"
                enabled: !root.onlineLoading && root.onlinePage > 1
                onClicked: root.performOnlineSearch(root.onlinePage - 1)
            }
            Label {
                Layout.fillWidth: true
                text: root.onlineLoading ? "Searching Workshop…" : root.onlineStatus
                elide: Text.ElideRight
                color: root.textMuted
                horizontalAlignment: Text.AlignHCenter
            }
            ToolButton {
                id: workshopNextPage
                objectName: "workshopNextPage"
                icon.name: "go-next"
                enabled: !root.onlineLoading && root.onlineHasMore
                onClicked: root.performOnlineSearch(root.onlinePage + 1)
            }
        }
        Rectangle {
            Layout.fillWidth: true
            visible: root.randomMode
            implicitHeight: randomControls.implicitHeight + 20
            radius: 10
            color: root.panelSurface
            border.color: root.borderSubtle
            ColumnLayout {
                id: randomControls
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: root.cfg_RandomDownloadEnabled ? "Random mode is active • downloads and switches one wallpaper at a time" : "Random mode is stopped"; font.bold: true; wrapMode: Text.WordWrap }
                    Button {
                        text: root.cfg_RandomDownloadEnabled ? "Stop" : "Start"
                        highlighted: root.cfg_RandomDownloadEnabled
                        onClicked: { root.cfg_RandomDownloadEnabled = !root.cfg_RandomDownloadEnabled; root.cfg_RandomizeWallpaper = root.cfg_RandomDownloadEnabled; root.configurationChanged() }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Switch / download every" }
                    SpinBox { from: 1; to: 10080; value: root.cfg_RandomDownloadDelayMinutes; onValueModified: { root.cfg_RandomDownloadDelayMinutes = value; root.cfg_SwitchTimer = value; root.configurationChanged() } }
                    Label { text: "minutes"; Layout.fillWidth: true }
                    ComboBox { model: ["Up to 12", "Up to 16", "Up to 18"]; currentIndex: root.cfg_RandomDownloadAgeLimit <= 12 ? 0 : (root.cfg_RandomDownloadAgeLimit <= 16 ? 1 : 2); onActivated: { root.cfg_RandomDownloadAgeLimit = [12,16,18][currentIndex]; root.configurationChanged() } }
                }
                Label { Layout.fillWidth: true; text: "Everything shown below was downloaded by Random mode. Use the normal filters or Delete to manage it."; opacity: 0.7; wrapMode: Text.WordWrap }
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
                anchors.margins: 0
                clip: true
                readonly property int columnCount: Math.max(1, Math.floor(width / 210))
                cellWidth: Math.floor(width / columnCount)
                cellHeight: Math.max(118, Math.round(cellWidth * 9 / 16))
                model: catalogModel
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 900
                flickDeceleration: 2600
                maximumFlickVelocity: 18000
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    width: 12
                }
                WheelHandler {
                    onWheel: function(event) {
                        // Precision touchpads send pixel deltas: preserve their
                        // native movement. Traditional wheels send angle deltas;
                        // move a useful amount without multiplying touchpad input.
                        var delta = root.wheelTravel(event.pixelDelta.y, event.angleDelta.y, grid.height)
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
                    required property bool compatibilityFallback
                    required property bool animatedCompatibility
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
                    required property var tags
                    required property string tagsText
                    required property string contentRating
                    required property string resolutionKey
                    required property int sourceWidth
                    required property int sourceHeight
                    required property string installState
                    required property string origin
                    required property real updatedEpoch
                    required property real subscriptions
                    required property real views
                    required property real rating
                    required property string workshopUrl
                    readonly property bool selected: Boolean(root.selectedItem && root.selectedItem.workshopId === workshopId)
                    readonly property bool applied: workshopId === root.appliedWorkshopId

                    objectName: "wallpaperCard"
                    width: grid.cellWidth - 6
                    height: grid.cellHeight - 6
                    x: 3
                    y: 3
                    radius: 6
                    color: cardMouse.containsMouse ? root.cardHover : root.cardSurface
                    border.width: selected ? 2 : (applied ? 1 : 0)
                    border.color: selected ? root.steamBlue : (applied ? Kirigami.Theme.positiveTextColor : "transparent")
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

                    AnimatedImage {
                        id: animatedCardPreview
                        objectName: "wallpaperCardPreview"
                        anchors.fill: parent
                        anchors.margins: 2
                        source: preview
                        asynchronous: true
                        cache: true
                        smooth: true
                        playing: visible
                        fillMode: Image.PreserveAspectFit
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 42
                        height: 42
                        source: "image-x-generic"
                        opacity: 0.45
                        visible: animatedCardPreview.status === Image.Null || animatedCardPreview.status === Image.Error
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 32
                        color: Qt.rgba(0, 0, 0, 0.82)
                        visible: cardMouse.containsMouse || parent.selected || parent.activeFocus
                        Label {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: title
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Kirigami.Icon {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 7
                        width: 20
                        height: 20
                        source: "emblem-default-symbolic"
                        color: Kirigami.Theme.positiveTextColor
                        visible: parent.applied
                    }
                    Kirigami.Icon {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 7
                        width: 20
                        height: 20
                        source: "download"
                        color: "white"
                        visible: online && !installed && (cardMouse.containsMouse || parent.selected)
                    }
                    function itemRecord() {
                        return {
                            title: title, workshopId: workshopId, kind: kind, renderKind: renderKind,
                            support: support, compatibilityFallback: compatibilityFallback, animatedCompatibility: animatedCompatibility, folder: folder, preview: preview, media: media,
                            sizeBytes: sizeBytes, previewWidth: previewWidth, previewHeight: previewHeight,
                            online: online, installed: installed, author: author, authorUrl: authorUrl,
                            creator: creator, description: description, tags: tags, tagsText: tagsText,
                            contentRating: contentRating, resolutionKey: resolutionKey,
                            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                            installState: installState, origin: origin,
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
        implicitWidth: 320
        width: 320
        Layout.preferredWidth: 320
        Layout.minimumWidth: 300
        Layout.maximumWidth: 340
        Layout.fillWidth: false
        Layout.fillHeight: true
        visible: !root.inspectorCollapsed
        color: Kirigami.Theme.backgroundColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            ScrollView {
                id: settingsScroll
                objectName: "settingsScroll"
                Layout.fillWidth: true
                Layout.maximumWidth: parent.width
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                WheelHandler {
                    target: null
                    onWheel: function(event) {
                        var flickable = settingsScroll.contentItem
                        var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120.0) * 48
                        var limit = Math.max(0, flickable.contentHeight - flickable.height)
                        flickable.contentY = Math.max(0, Math.min(limit, flickable.contentY - delta))
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    width: Math.min(settingsScroll.availableWidth, 320)
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
                    text: root.selectedItem ? (String(root.selectedItem.kind || "unknown").toUpperCase() + "  •  Workshop " + String(root.selectedItem.workshopId || "")) : "Select a wallpaper to inspect and customize"
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
                    Layout.preferredWidth: 300
                    Layout.maximumWidth: 320
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: width * 9 / 16
                    radius: 10
                    color: root.appSurface
                    clip: true
                    AnimatedImage {
                        id: selectedPreviewImage
                        objectName: "selectedPreviewImage"
                        anchors.fill: parent
                        anchors.margins: 3
                        source: root.selectedItem ? root.selectedItem.preview : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: true
                        playing: visible
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
                            objectName: "nativeWorkshopSubscribe"
                            Layout.fillWidth: true
                            text: root.onlineAwaitingInstall ? "Downloading…" : "Download"
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
                    spacing: 6
                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading {
                            text: "Wallpaper options"
                            level: 3
                            Layout.fillWidth: true
                        }
                        ToolButton {
                            id: wallpaperOptionsToggle
                            objectName: "wallpaperOptionsToggle"
                            icon.name: root.wallpaperOptionsExpanded ? "arrow-up" : "arrow-down"
                            ToolTip.visible: hovered
                            ToolTip.text: root.wallpaperOptionsExpanded ? "Hide wallpaper-specific options" : "Show wallpaper-specific options"
                            onClicked: root.wallpaperOptionsExpanded = !root.wallpaperOptionsExpanded
                        }
                        Button {
                            text: "Reset"
                            flat: true
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
                    visible: root.wallpaperOptionsExpanded && !root.propertiesLoading && count > 0
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
                                visible: presentation || modelData.type !== "bool"
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
                                objectName: "wallpaperBooleanEditor"
                                Layout.fillWidth: true
                                visible: modelData.editable && modelData.type === "bool"
                                text: root.friendlyPropertyLabel(modelData)
                                contentItem: Label {
                                    text: parent.text
                                    wrapMode: Text.WordWrap
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: parent.indicator.width + parent.spacing
                                }
                                checked: Boolean(root.wallpaperPropertyValue(modelData.name, modelData.default))
                                onToggled: root.setWallpaperProperty(modelData.name, checked)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: modelData.editable && modelData.type === "slider"
                                RowLayout {
                                    Layout.fillWidth: true
                                    Slider {
                                        objectName: "wallpaperSliderEditor"
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
                    spacing: 6
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
                ToolButton {
                    id: advancedToggle
                    objectName: "advancedToggle"
                    text: root.advancedExpanded ? "Hide advanced options" : "Advanced options"
                    icon.name: root.advancedExpanded ? "arrow-up" : "arrow-down"
                    display: AbstractButton.TextBesideIcon
                    onClicked: root.advancedExpanded = !root.advancedExpanded
                }
                ColumnLayout {
                    id: steamLibrarySection
                    objectName: "advancedOptions"
                    Layout.fillWidth: true
                    visible: root.advancedExpanded
                    spacing: 6
                    Label {
                        text: "Steam library"
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Choose the Steam library that contains Wallpaper Engine. Dcent finds Workshop downloads in its steamapps folder automatically."
                        opacity: 0.75
                        wrapMode: Text.WordWrap
                    }
                    TextField {
                        id: steamLibraryPathField
                        objectName: "steamLibraryPathField"
                        Layout.fillWidth: true
                        text: root.cfg_SteamLibraryPath
                        placeholderText: "For example: /data/SteamLibrary"
                        selectByMouse: true
                        onEditingFinished: root.setSteamLibraryPath(text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: "Choose folder…"
                            icon.name: "folder-open"
                            onClicked: steamLibraryFolderDialog.open()
                        }
                        Button {
                            text: "Rescan library"
                            icon.name: "view-refresh"
                            onClicked: root.setSteamLibraryPath(steamLibraryPathField.text)
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.localCatalogRefreshing
                              ? "Scanning Workshop items…"
                              : ("Workshop folder: " + root.cfg_WorkshopRoot)
                        opacity: 0.62
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: 11
                    }
                }
                Kirigami.Separator {
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    id: legacyRandomDownloadSettings
                    Layout.fillWidth: true
                    visible: false
                    spacing: 6
                    Label { text: "Random Workshop downloads"; font.bold: true }
                    CheckBox {
                        text: "Keep my library supplied with random wallpapers"
                        checked: root.cfg_RandomDownloadEnabled
                        onToggled: { root.cfg_RandomDownloadEnabled = checked; root.configurationChanged() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.cfg_RandomDownloadEnabled
                        Label { text: "Every" }
                        SpinBox { from: 1; to: 10080; value: root.cfg_RandomDownloadDelayMinutes; onValueModified: { root.cfg_RandomDownloadDelayMinutes = value; root.configurationChanged() } }
                        Label { text: "minutes"; Layout.fillWidth: true }
                    }
                    ComboBox {
                        Layout.fillWidth: true
                        visible: root.cfg_RandomDownloadEnabled
                        model: ["Up to 12", "Up to 16", "Up to 18"]
                        currentIndex: root.cfg_RandomDownloadAgeLimit <= 12 ? 0 : (root.cfg_RandomDownloadAgeLimit <= 16 ? 1 : 2)
                        onActivated: { root.cfg_RandomDownloadAgeLimit = [12, 16, 18][currentIndex]; root.configurationChanged() }
                    }
                    Label { Layout.fillWidth: true; visible: root.cfg_RandomDownloadEnabled; text: "Downloads one unseen item at a time through your signed-in Steam client. Random downloads receive the Random download tag and can be filtered or deleted normally."; opacity: 0.65; wrapMode: Text.WordWrap }
                }
                Kirigami.Separator { Layout.fillWidth: true }
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
                    visible: root.advancedExpanded
                    text: "Login screen"
                    font.bold: true
                }
                Label {
                    visible: root.advancedExpanded
                    text: "Use the selected wallpaper's still preview through KDE's built-in login provider. Live scene, web, audio, and mouse processing stay disabled before login for stability."
                    opacity: 0.65
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Button {
                    Layout.fillWidth: true
                    visible: root.advancedExpanded
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
                        if (root.selectedItem && root.selectedItem.kind === "scene") {
                            root.invalidateSceneRender("Scaling changed • preparation will rebuild the animated scene")
                            root.configurationChanged()
                        } else {
                            root.settingsEdited()
                        }
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
                    visible: root.advancedExpanded
                    Label { text: "FPS"; Layout.fillWidth: true }
                    SpinBox {
                        from: 15
                        to: 240
                        value: root.cfg_Fps
                        onValueModified: {
                            root.cfg_Fps = value
                            if (root.selectedItem && root.selectedItem.kind === "scene") {
                                root.invalidateSceneRender("Frame rate changed • preparation will rebuild the animated scene")
                                root.configurationChanged()
                            } else {
                                root.settingsEdited()
                            }
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
                        root.settingsEdited()
                    }
                }
                CheckBox {
                    text: "Mute audio"
                    checked: root.cfg_Muted
                    onToggled: {
                        root.cfg_Muted = checked
                        root.cfg_MuteAudio = checked
                        root.settingsEdited()
                    }
                }
                CheckBox {
                    text: "System audio reactivity"
                    checked: root.cfg_SystemAudioCapture
                    onToggled: {
                        root.cfg_SystemAudioCapture = checked
                        root.settingsEdited()
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
                        root.settingsEdited()
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
                    enabled: !root.cfg_WallpaperSource.endsWith("+scene")
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
                    enabled: !root.cfg_WallpaperSource.endsWith("+scene")
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
                        root.settingsEdited()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.kdeAllScreensEnabled
                    Label { text: "Rotation"; Layout.fillWidth: true }
                    ComboBox {
                        model: ["0°", "90°", "180°", "270°"]
                        currentIndex: Math.max(0, [0, 90, 180, 270].indexOf(root.cfg_Rotation))
                        onActivated: {
                            root.cfg_Rotation = [0, 90, 180, 270][currentIndex]
                            root.settingsEdited()
                        }
                    }
                }
                Label {
                    visible: root.kdeAllScreensEnabled
                    Layout.fillWidth: true
                    text: "Rotation is fixed to normal while applying one wallpaper to every screen."
                    opacity: 0.65
                    wrapMode: Text.WordWrap
                }
                Label { text: "Pause behavior"; font.bold: true }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["Never pause", "Any window", "Maximized window", "Focused window", "Focused or maximized", "Fullscreen window"]
                    currentIndex: Math.max(0, root.cfg_PauseMode)
                    onActivated: {
                        root.cfg_PauseMode = currentIndex
                        root.settingsEdited()
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
                        root.settingsEdited()
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
            Label {
                id: applyStatusLabel
                objectName: "applyStatusLabel"
                Layout.fillWidth: true
                text: root.applyStatus
                color: root.applyStatus.indexOf("Applied") === 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                opacity: root.applyStatus.indexOf("Applied") === 0 ? 1.0 : 0.7
                wrapMode: Text.WordWrap
            }
        }
    }
}
