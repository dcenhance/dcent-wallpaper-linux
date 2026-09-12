import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "KdeAllScreensGate"
    when: windowShown

    Component {
        id: dialogComponent
        QtObject {
            property bool allScreens: false
            property var wallpaperConfiguration: null
            property int applyCount: 0
            function applyWallpaper() { applyCount += 1 }
        }
    }

    Component {
        id: kcmDialogComponent
        QtObject {
            property bool allScreens: false
            property var selectedScreen: ({name: "DP-1"})
            property var wallpaperConfiguration: null
        }
    }

    Component {
        id: realKcmDialogComponent
        QtObject {
            property bool allScreens: false
            property var selectedScreen: ({name: "DP-1"})
            property var wallpaperConfiguration: null
            property int applyCount: 0
            function applyWallpaper() { applyCount += 1 }
        }
    }

    function test_multiscreen_section_follows_kde_switch() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        verify(dialog !== null)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        verify(page !== null)
        const section = findChild(page, "multiScreenSection")
        const modePicker = findChild(page, "multiScreenModePicker")
        verify(section !== null)
        verify(modePicker !== null)

        compare(page.kdeAllScreensEnabled, false)
        compare(section.gateOpen, false)
        compare(section.visible, false)
        page.cfg_MultiScreenMode = "span"
        page.cfg_VirtualDesktopWidth = 5120
        page.cfg_VirtualDesktopHeight = 1440
        const localConfig = page.exportConfiguration()
        compare(localConfig.MultiScreenMode, "single")
        compare(localConfig.VirtualDesktopWidth, 0)
        compare(localConfig.VirtualDesktopHeight, 0)

        dialog.allScreens = true
        tryCompare(page, "kdeAllScreensEnabled", true)
        tryCompare(section, "gateOpen", true)
        compare(modePicker.count, 2)
        verify(modePicker.model.indexOf("Different wallpaper per screen") < 0)

        page.cfg_MultiScreenMode = "single"
        const normalizedAllScreensConfig = page.exportConfiguration()
        compare(normalizedAllScreensConfig.MultiScreenMode, "mirror")

        page.cfg_MultiScreenMode = "span"
        const allScreensConfig = page.exportConfiguration()
        compare(allScreensConfig.MultiScreenMode, "span")
        compare(allScreensConfig.VirtualDesktopWidth, 5120)
        compare(allScreensConfig.VirtualDesktopHeight, 1440)
    }

    function test_animated_scene_fallback_stages_video_backend() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        verify(dialog !== null)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        verify(page !== null)
        const item = {
            title: "Animated scene",
            workshopId: "2904412422",
            kind: "scene",
            renderKind: "image",
            support: "Preview fallback",
            folder: "/tmp/2904412422",
            preview: "file:///tmp/workshop-preview.gif",
            media: "/tmp/2904412422/scene.json"
        }
        page.selectedItem = item
        page.selectionGeneration = 7
        page.sceneChecking = true

        page.finishSceneFallback(7, item, "native renderer blocked", {
            ok: true,
            kind: "video",
            animated: true,
            path: "/tmp/animated-fallback.mp4",
            preview: "/tmp/animated-poster.png",
            width: 3840,
            height: 2160
        })

        compare(page.sceneChecking, false)
        compare(page.cfg_WallpaperType, "video")
        compare(page.cfg_MediaPath, "/tmp/animated-fallback.mp4")
        compare(page.cfg_WallpaperSource, "/tmp/animated-fallback.mp4+video")
        compare(page.cfg_PreviewPath, "/tmp/animated-poster.png")
        verify(page.applyStatus.indexOf("animated") >= 0)
    }

    function test_wallpaper_engine_properties_are_separate_dynamic_and_exported() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        verify(page !== null)
        const propertyList = findChild(page, "wallpaperEnginePropertyList")
        verify(propertyList !== null)
        page.selectedItem = {workshopId: "properties", kind: "web", online: false, installed: true}
        page.selectionGeneration = 1
        page.stagedSelectionGeneration = 1
        page.stagedWorkshopId = "properties"
        page.selectedSourceReady = true
        page.cfg_WallpaperWorkShopId = "properties"

        page.applyProjectInfo({
            editablePropertyCount: 2,
            properties: [
                {name: "heading", type: "group", label: "Project controls", editable: false, condition: "", value: "", default: "", presetValue: ""},
                {name: "enabled", type: "bool", label: "Enabled", editable: true, condition: "", value: true, default: true, presetValue: true},
                {name: "amount", type: "slider", label: "Amount", editable: true, condition: "enabled.value", value: 4, default: 4, presetValue: 4, min: 0, max: 10, step: 1, precision: 0}
            ],
            userOverrides: {},
            presetOverrides: {}
        }, "")
        tryCompare(propertyList, "count", 3)

        page.setWallpaperProperty("enabled", false)
        tryCompare(propertyList, "count", 2)
        compare(JSON.parse(page.cfg_PropertyOverrides).enabled, false)
        compare(page.exportConfiguration().PropertyOverrides, page.cfg_PropertyOverrides)
    }

    function test_wallpaper_asset_choices_are_exposed_inside_wallpaper_settings() {
        const request = new XMLHttpRequest()
        request.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        request.send()
        const source = request.responseText

        verify(source.indexOf('objectName: "wallpaperAssetPicker"') >= 0)
        verify(source.indexOf("model: modelData.assetOptions || []") >= 0)
        verify(source.indexOf("root.setWallpaperProperty(modelData.name, model[currentIndex].value)") >= 0)
    }

    function test_property_labels_colors_and_pluralization_are_user_facing() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        compare(page.friendlyPropertyLabel({name: "ui_browse_properties_scheme_color", label: "ui_browse_properties_scheme_color"}), "Color scheme")
        compare(page.friendlyPropertyLabel({name: "signature", label: "Artist's Signature"}), "Artist's Signature")
        compare(page.wallpaperColorDisplay("0.69803922 0 0", 3), "#B20000")
        compare(page.propertyCapabilities({propertyTypeCounts: {bool: 1, color: 1}}), "1 toggle • 1 color")
        page.applyProjectInfo({properties: [{name: "enabled", label: "Enabled", type: "bool", value: true, editable: true}], editablePropertyCount: 1}, "")
        compare(page.propertyStatus, "1 of 1 property editable")
    }

    function test_combo_matching_keeps_scalar_types_distinct() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const spec = {
            name: "mode", default: 1,
            options: [
                {label: "False", value: false},
                {label: "True", value: true},
                {label: "Number", value: 1},
                {label: "String", value: "1"}
            ]
        }

        page.propertyValues = ({mode: 1})
        compare(page.comboPropertyIndex(spec), 2)
        page.propertyValues = ({mode: "1"})
        compare(page.comboPropertyIndex(spec), 3)
    }

    function test_resource_pickers_store_native_paths_not_file_urls() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("selectedFile.toLocalFile()") >= 0)
        verify(source.indexOf("selectedFolder.toLocalFile()") >= 0)
        verify(source.indexOf("selectedFile.toString()") < 0)
        verify(source.indexOf("selectedFolder.toString()") < 0)
        verify(source.indexOf("root.browseFileType === \"video\"") >= 0)
        verify(source.indexOf("root.browseFileType === \"image\"") >= 0)
        verify(source.indexOf("visible: Boolean(modelData.allowTextEntry)") >= 0)
    }

    function test_web_directory_properties_have_fetchall_and_ondemand_contracts() {
        const viewRequest = new XMLHttpRequest()
        viewRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/backend/QtWebView.qml"), false)
        viewRequest.send()
        const view = viewRequest.responseText
        const mainRequest = new XMLHttpRequest()
        mainRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/main.qml"), false)
        mainRequest.send()
        const main = mainRequest.responseText
        verify(view.indexOf("wallpaperRequestRandomFileForProperty") >= 0)
        verify(view.indexOf("userDirectoryFilesAddedOrChanged") >= 0)
        verify(view.indexOf("userDirectoryFilesRemoved") >= 0)
        verify(view.indexOf("listDirectory") >= 0)
        verify(view.indexOf("function deliverUserPropertiesDirect") >= 0)
        verify(view.indexOf("web.runJavaScript") >= 0)
        verify(view.indexOf('property url source: ""') >= 0)
        verify(view.indexOf('url: "about:blank"') >= 0)
        verify(view.indexOf("userScripts.collection = [") >= 0)
        verify(view.indexOf("userScripts.insert([") < 0)
        verify(view.indexOf("Qt.callLater(function()") >= 0)
        verify(view.indexOf("web.url = webItem.source") >= 0)
        verify(view.indexOf("[DEBUG-webprops]") < 0)
        verify(view.indexOf("DcentHideWallpaperDiagnostics") >= 0)
        verify(view.indexOf("window.log.htmlElement") >= 0)
        verify(view.indexOf("DcentWallpaperProperties") < 0)
        verify(view.indexOf("QWebChannelSource") < 0)
        verify(view.indexOf('import "../WebViewport.js" as WebViewport') >= 0)
        verify(view.indexOf('property string layoutMode: "fill"') >= 0)
        verify(view.indexOf("property int referenceWidth: 1920") >= 0)
        verify(view.indexOf("WebViewport.compute") >= 0)
        verify(view.indexOf("zoomFactor: webItem.viewport.scaleX") >= 0)
        verify(main.indexOf("listDirectory: pyext.list_property_directory") >= 0)
        verify(main.indexOf("workshopId: background.projectIdFromPath()") >= 0)
        verify(main.indexOf("layoutMode: background.scaling") >= 0)
        const bridgeRequest = new XMLHttpRequest()
        bridgeRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/Pyext.qml"), false)
        bridgeRequest.send()
        verify(bridgeRequest.responseText.indexOf("onClientConnected: function(webSocket)") >= 0)
    }

    function test_audio_reactive_backends_use_native_captsilver_monitor_capture() {
        function source(path) {
            const request = new XMLHttpRequest()
            request.open("GET", Qt.resolvedUrl(path), false)
            request.send()
            return request.responseText
        }
        const view = source("../../plasma-plugin/contents/ui/backend/QtWebView.qml")
        const scene = source("../../plasma-plugin/contents/ui/backend/Scene.qml")
        const main = source("../../plasma-plugin/contents/ui/main.qml")
        const config = source("../../plasma-plugin/contents/ui/config.qml")
        const schema = source("../../plasma-plugin/contents/config/main.xml")

        verify(main.indexOf("import com.github.captsilver.wallpaperEngineKde") >= 0)
        verify(main.indexOf("property bool systemAudioCapture: wallpaper.configuration.SystemAudioCapture") >= 0)
        verify(view.indexOf("import com.github.captsilver.wallpaperEngineKde") >= 0)
        verify(view.indexOf("WebAudioBridge {") >= 0)
        verify(view.indexOf("enabled: background.systemAudioCapture") >= 0)
        verify(view.indexOf("webobj.sigAudio(samples)") >= 0)
        verify(scene.indexOf("import com.github.captsilver.wallpaperEngineKde") >= 0)
        verify(scene.indexOf("systemAudioCapture: background.systemAudioCapture") >= 0)
        verify(scene.indexOf("userProperties: String(sceneItem.userPropsJson)") >= 0)
        verify(config.indexOf("property bool cfg_SystemAudioCapture: true") >= 0)
        verify(schema.indexOf('entry name="SystemAudioCapture" type="Bool"') >= 0)
    }

    function test_catalog_startup_selects_exact_configured_workshop_id() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {
            configDialog: dialog,
            cfg_WallpaperPath: "/data/SteamLibrary/steamapps/workshop/content/431960/837440254",
            cfg_WallpaperWorkShopId: "837440254",
            cfg_WallpaperSource: "/data/SteamLibrary/steamapps/workshop/content/431960/837440254/index.html+web",
            localCatalog: [{
                title: "3D Solar System", workshopId: "837440254", kind: "web", renderKind: "web",
                support: "Web runtime", folder: "/data/SteamLibrary/steamapps/workshop/content/431960/837440254",
                preview: "file:///tmp/solar.jpg",
                media: "/data/SteamLibrary/steamapps/workshop/content/431960/837440254/index.html",
                online: false, installed: true
            }]
        })
        verify(page.selectedItem !== null)
        compare(page.selectedItem.workshopId, "837440254")
    }

    function test_current_wallpaper_starts_with_clear_no_changes_status() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {
            configDialog: dialog,
            cfg_WallpaperPath: "/tmp/current",
            cfg_WallpaperWorkShopId: "3333333333",
            cfg_WallpaperSource: "/tmp/current/video.mp4+video",
            localCatalog: [{
                title: "Current", workshopId: "3333333333", kind: "video", renderKind: "video",
                support: "Video", folder: "/tmp/current", preview: "file:///tmp/current.jpg",
                media: "/tmp/current/video.mp4", online: false, installed: true
            }]
        })
        verify(page.selectedItem !== null)
        compare(page.appliedWorkshopId, "3333333333")
        compare(page.applyStatus, "Currently applied • no unapplied changes")
    }

    function test_compact_kcm_switches_between_library_and_full_width_details() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog, width: 660, height: 620})
        const libraryPane = findChild(page, "libraryPane")
        const inspectorPanel = findChild(page, "inspectorPanel")
        const quickApply = findChild(page, "quickApplyButton")
        verify(page.compactLayout)
        verify(page.inspectorCollapsed)
        verify(libraryPane !== null)
        verify(inspectorPanel !== null)
        verify(quickApply !== null)
        page.chooseWallpaper({
            title: "Compact selection", workshopId: "5555555555", kind: "scene", renderKind: "scene",
            support: "Animated scene", folder: "/tmp/compact", preview: "file:///tmp/compact.jpg",
            media: "/tmp/compact/scene.json", online: false, installed: true
        })
        compare(page.inspectorCollapsed, false)
        compare(libraryPane.visible, false)
        page.applyProjectInfo({}, "")
        page.inspectorCollapsed = true
        verify(quickApply.enabled)
    }

    function test_inspector_can_collapse_for_cleaner_library_browsing() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const panel = findChild(page, "inspectorPanel")
        const toggle = findChild(page, "inspectorToggle")
        verify(panel !== null)
        verify(toggle !== null)
        page.inspectorCollapsed = true
        compare(panel.visible, false)
        page.inspectorCollapsed = false
        compare(page.inspectorCollapsed, false)
    }

    function test_single_configure_view_separates_wallpaper_and_dcent_settings() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        verify(page !== null)
        verify(findChild(page, "catalogLibraryTab") !== null)
        verify(findChild(page, "catalogWorkshopTab") !== null)
        compare(findChild(page, "inspectorOverviewTab"), null)
        compare(findChild(page, "inspectorCustomizeTab"), null)
        compare(findChild(page, "inspectorPlaybackTab"), null)
        verify(findChild(page, "configureHeading") !== null)
        verify(findChild(page, "wallpaperSettingsSection") !== null)
        verify(findChild(page, "dcentGeneralSettingsSection") !== null)
        verify(findChild(page, "selectedPreviewPlaceholder") !== null)

        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("readonly property color steamBlue: Kirigami.Theme.highlightColor") >= 0)
        verify(source.indexOf("readonly property color appSurface: Kirigami.Theme.backgroundColor") >= 0)
        verify(source.indexOf("readonly property color cardSurface: Kirigami.Theme.alternateBackgroundColor") >= 0)
        verify(source.indexOf("Kirigami.Heading") >= 0)
        verify(source.indexOf("Kirigami.Separator") >= 0)
        verify(source.indexOf("Layout.preferredWidth: root.compactLayout ? root.width : 420") >= 0)
        verify(source.indexOf("maximumLineCount: 2") >= 0)
        verify(source.indexOf("retainWhileLoading: false") >= 0)
        verify(source.indexOf("fillMode: Image.PreserveAspectCrop") >= 0)
        verify(source.indexOf("spacing: 2") >= 0)
        verify(source.indexOf("height: propertyEditorColumn.implicitHeight + 8") >= 0)
        verify(source.indexOf("Layout.preferredHeight: 150") >= 0)
        verify(source.indexOf("readonly property int columnCount") >= 0)
        verify(source.indexOf("readonly property bool applied: workshopId === root.appliedWorkshopId") >= 0)
        verify(source.indexOf('text: applied ? "Applied" : "Selected"') >= 0)
        verify(source.indexOf("Accessible.name: title") >= 0)
        verify(source.indexOf("ToolTip.text: title") >= 0)
        verify(source.indexOf('text: !root.kdeAllScreensEnabled ? "Apply to selected screen"') >= 0)
        verify(source.indexOf('objectName: "wallpaperEnginePropertyList"') >= 0)
        verify(source.indexOf('objectName: "wallpaperSettingsSection"') >= 0)
        verify(source.indexOf('objectName: "dcentGeneralSettingsSection"') >= 0)
        verify(source.indexOf('text: "Wallpaper settings"') >= 0)
        verify(source.indexOf('text: "DcentWallpapers settings"') >= 0)
        verify(source.indexOf('text: "Overview"') < 0)
        verify(source.indexOf('text: "Customize"') < 0)
        verify(source.indexOf('text: "Playback"') < 0)
        verify(source.indexOf("ScrollBar.horizontal.policy: ScrollBar.AlwaysOff") >= 0)
        verify(source.indexOf("interactive: false") >= 0)
        verify(source.indexOf('readonly property color steamBlue: "#66c0f4"') < 0)
        verify(source.indexOf('readonly property color appSurface: "#0e141b"') < 0)
        verify(!/#[0-9A-Fa-f]{6}/.test(source))
        verify(source.indexOf('text: installed ? "INSTALLED" : "DOWNLOAD"') >= 0)
        verify(source.indexOf('visible: modelData.editable && modelData.type === "color"') >= 0)
    }

    function test_workshop_download_runs_in_background_without_steam_window() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("scenePreflightBridge.workshop_download") >= 0)
        verify(source.indexOf("workshopWebView.url = \"https://steamcommunity.com/sharedfiles/filedetails") < 0)
        verify(source.indexOf("workshopDetailsDialog.open()") < 0)
    }

    function test_workshop_download_applies_automatically_when_finished() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("property bool pendingAutoApply: false") >= 0)
        verify(source.indexOf("pendingAutoApply = true") >= 0)
        verify(source.indexOf("var applyWhenReady = root.pendingAutoApply") >= 0)
        verify(source.indexOf("root.loadInstalledOnlineItem(root.selectedItem, applyWhenReady)") >= 0)
        verify(source.indexOf("Downloaded • applying automatically") >= 0)
    }

    function test_runtime_reloads_backend_when_switching_same_type_wallpapers() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/main.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("type_changed || path_changed || is_infobackend") >= 0)
        verify(source.indexOf("backendLoader.item.source = path") < 0)
        verify(source.indexOf("wallpaper.configuration.WallpaperPath = Common.urlNative(model.path)") >= 0)
        verify(source.indexOf("wallpaper.configuration.PreviewPath = Common.urlNative(Common.getWpModelPreviewSource(model))") >= 0)
        verify(source.indexOf("wallpaper.configuration.PropertyOverrides = \"\"") >= 0)
        verify(source.indexOf("Math.floor(Math.random() * wpListModel.model.count)") >= 0)
        verify(source.indexOf("property int optionLoadGeneration: 0") >= 0)
        verify(source.indexOf("generation !== background.optionLoadGeneration || workshopId !== background.workshopid") >= 0)
        const configRequest = new XMLHttpRequest()
        configRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        configRequest.send()
        verify(configRequest.responseText.indexOf("onSingleTapped") >= 0)
        verify(configRequest.responseText.indexOf("onDoubleTapped") >= 0)
        verify(configRequest.responseText.indexOf("Accessible.onPressAction") >= 0)
        verify(configRequest.responseText.indexOf("acceptedButtons: Qt.NoButton") >= 0)
        verify(configRequest.responseText.indexOf("function syncAllScreens(configuration)") >= 0)
        verify(configRequest.responseText.indexOf("var requestedWorkshopId = configuration.WallpaperWorkShopId") >= 0)
        verify(configRequest.responseText.indexOf("generation !== root.localCatalogGeneration || workshopRoot !== root.cfg_WorkshopRoot") >= 0)
    }

    function test_runtime_keeps_current_wallpaper_until_replacement_first_frame() {
        const request = new XMLHttpRequest()
        request.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/main.qml"), false)
        request.send()
        const source = request.responseText

        verify(source.indexOf("property var retiringItem: null") >= 0)
        verify(source.indexOf("function finishBackendSwap()") >= 0)
        verify(source.indexOf("function onSig_backendFirstFrame") >= 0)
        verify(source.indexOf("this.item.destroy(100)") < 0)
    }

    function test_clickable_web_wallpapers_capture_desktop_left_clicks_when_enabled() {
        const mainRequest = new XMLHttpRequest()
        mainRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/main.qml"), false)
        mainRequest.send()
        const main = mainRequest.responseText
        const webRequest = new XMLHttpRequest()
        webRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/backend/QtWebView.qml"), false)
        webRequest.send()
        const web = webRequest.responseText
        const configRequest = new XMLHttpRequest()
        configRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        configRequest.send()
        const config = configRequest.responseText

        verify(main.indexOf('objectName: "interactiveWallpaperMouseGrabber"') >= 0)
        verify(main.indexOf("z: 1000000") >= 0)
        verify(main.indexOf("this.mouseHooker.destroy()") >= 0)
        verify(main.indexOf("z: -1") < 0)
        verify(web.indexOf("activeFocusOnPress: true") >= 0)
        verify(config.indexOf('text: "Interactive wallpaper mode"') >= 0)
    }

    function test_catalog_path_matching_never_selects_id_prefix_neighbor() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        verify(page.pathBelongsToItem("/data/431960/1234", "/data/431960/1234"))
        verify(page.pathBelongsToItem("/data/431960/1234/index.html", "/data/431960/1234"))
        verify(!page.pathBelongsToItem("/data/431960/12345/index.html", "/data/431960/1234"))
    }

    function test_double_click_activation_is_owned_by_the_new_selection() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const item = {
            title: "Activated", workshopId: "6666666666", kind: "scene", renderKind: "scene",
            support: "Animated scene", folder: "/tmp/activated", preview: "file:///tmp/activated.jpg",
            media: "/tmp/activated/scene.json", online: false, installed: true
        }
        page.activateGalleryItem(item)
        compare(page.selectedItem.workshopId, "6666666666")
        verify(page.applyAfterSceneCheck)
        compare(page.stagedWorkshopId, "")
    }

    function test_double_click_on_ready_selection_applies_immediately() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const item = {
            title: "Ready web wallpaper", workshopId: "7777777776", kind: "web", renderKind: "web",
            support: "Web runtime", folder: "/tmp/ready-web", preview: "file:///tmp/ready.jpg",
            media: "/tmp/ready-web/index.html", online: false, installed: true
        }
        page.selectedItem = item
        page.selectionGeneration = 8
        page.stagedSelectionGeneration = 8
        page.stagedWorkshopId = item.workshopId
        page.selectedSourceReady = true
        page.cfg_WallpaperWorkShopId = item.workshopId
        page.cfg_WallpaperPath = item.folder
        page.cfg_MediaPath = item.media
        page.cfg_WallpaperType = "web"
        page.cfg_WallpaperSource = item.media + "+web"

        page.activateGalleryItem(item)

        compare(dialog.applyCount, 1)
        compare(page.selectionGeneration, 8)
        compare(page.appliedWorkshopId, item.workshopId)
    }

    function test_every_apply_button_exposes_repeatable_accessible_press_action() {
        const request = new XMLHttpRequest()
        request.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        request.send()
        const source = request.responseText

        verify(/objectName:\s*"quickApplyButton"[\s\S]*?Accessible\.onPressAction:\s*root\.applyNow\(\)/.test(source))
        verify(/objectName:\s*"primaryApplyButton"[\s\S]*?Accessible\.onPressAction:\s*root\.applyNow\(\)/.test(source))
    }

    function test_stale_installed_online_lookup_cannot_replace_newer_selection() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const online = {
            title: "Online A", workshopId: "1111111111", kind: "video", renderKind: "video",
            folder: "", preview: "https://example.invalid/a.jpg", media: "", online: true, installed: true
        }
        page.loadInstalledOnlineItem(online)
        const requestGeneration = page.selectionGeneration
        const local = {
            title: "Local B", workshopId: "2222222222", kind: "video", renderKind: "video",
            support: "Video", folder: "/tmp/b", preview: "file:///tmp/b.jpg", media: "/tmp/b.mp4",
            online: false, installed: true
        }
        page.selectGalleryItem(local)

        compare(page.selectedItem.workshopId, "2222222222")
        verify(!page.selectionRequestMatches(requestGeneration, "1111111111"))
    }

    function test_kde_save_is_side_effect_free_while_scene_is_pending() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        let changes = 0
        page.configurationChanged.connect(function() { changes += 1 })
        page.chooseWallpaper({
            title: "Pending scene",
            workshopId: "7777777777",
            kind: "scene",
            renderKind: "scene",
            support: "Animated scene",
            folder: "/tmp/pending-scene",
            preview: "file:///tmp/pending-scene.jpg",
            media: "/tmp/pending-scene/scene.json",
            online: false,
            installed: true
        })

        compare(changes, 0)
        page.saveConfig()
        compare(page.applyAfterSceneCheck, false)
        compare(page.cfg_WallpaperWorkShopId, "")
    }

    function test_kcm_custom_apply_targets_selected_screen_directly() {
        const dialog = createTemporaryObject(kcmDialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.screen = dialog.selectedScreen
        compare(page.selectedScreenTarget(), "DP-1")
        page.selectedItem = {workshopId: "B", kind: "video", online: false, installed: true}
        page.selectionGeneration = 3
        page.stagedSelectionGeneration = 3
        page.stagedWorkshopId = "B"
        page.selectedSourceReady = true
        page.cfg_WallpaperWorkShopId = "B"
        page.cfg_WallpaperPath = "/tmp/b"
        page.cfg_MediaPath = "/tmp/b.mp4"
        page.cfg_WallpaperType = "video"
        page.cfg_WallpaperSource = "/tmp/b.mp4+video"
        page.commitApply()
        compare(page.applyStatus, "Applying to selected screen…")
    }

    function test_selected_screen_name_survives_qscreen_replacement_after_first_apply() {
        const dialog = createTemporaryObject(kcmDialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.screen = dialog.selectedScreen
        compare(page.selectedScreenTarget(), "DP-1")

        page.screen = null
        dialog.selectedScreen = null

        compare(page.selectedScreenTarget(), "DP-1")
    }

    function test_custom_apply_prefers_exact_selected_screen_over_outer_kcm_apply() {
        const dialog = createTemporaryObject(realKcmDialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.screen = dialog.selectedScreen
        page.selectedItem = {title: "B", workshopId: "B", kind: "video", renderKind: "video", online: false, installed: true}
        page.selectionGeneration = 3
        page.stagedSelectionGeneration = 3
        page.stagedWorkshopId = "B"
        page.selectedSourceReady = true
        page.cfg_WallpaperWorkShopId = "B"
        page.cfg_WallpaperPath = "/tmp/b"
        page.cfg_MediaPath = "/tmp/b.mp4"
        page.cfg_WallpaperType = "video"
        page.cfg_WallpaperSource = "/tmp/b.mp4+video"

        page.commitApply()

        compare(dialog.applyCount, 0)
        compare(page.applyStatus, "Applying to selected screen…")
        compare(page.selectedScreenTarget(), "DP-1")
    }

    function test_apply_falls_back_to_kde_when_qscreen_identity_is_unavailable() {
        const dialog = createTemporaryObject(realKcmDialogComponent, testCase)
        dialog.selectedScreen = null
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.selectedItem = {title: "B", workshopId: "B", kind: "web", renderKind: "web", online: false, installed: true}
        page.selectionGeneration = 4
        page.stagedSelectionGeneration = 4
        page.stagedWorkshopId = "B"
        page.selectedSourceReady = true
        page.cfg_WallpaperWorkShopId = "B"
        page.cfg_WallpaperPath = "/tmp/b"
        page.cfg_MediaPath = "/tmp/b/index.html"
        page.cfg_WallpaperType = "web"
        page.cfg_WallpaperSource = "/tmp/b/index.html+web"

        page.commitApply()

        compare(dialog.applyCount, 1)
        compare(page.applyStatus, "Applied to KDE's selected screen")
    }

    function test_staged_source_ownership_blocks_previous_wallpaper_commit() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.selectedItem = {workshopId: "B", kind: "video", online: false, installed: true}
        page.selectionGeneration = 2
        page.selectedSourceReady = true
        page.stagedSelectionGeneration = 1
        page.stagedWorkshopId = "A"
        page.cfg_WallpaperWorkShopId = "A"
        page.cfg_WallpaperSource = "/tmp/a.mp4+video"
        page.commitApply()
        compare(dialog.applyCount, 0)
        compare(page.applyStatus, "Selected wallpaper is not ready yet")
    }

    function test_inspector_preview_follows_selected_item_atomically() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.cfg_PreviewPath = "/tmp/classified-old.jpg"
        page.cfg_WallpaperWorkShopId = "2810836257"
        page.chooseWallpaper({
            title: "Guardian",
            workshopId: "2080115941",
            kind: "scene",
            renderKind: "scene",
            support: "Animated scene",
            folder: "/tmp/guardian",
            preview: "file:///tmp/guardian.jpg",
            media: "/tmp/guardian/scene.json",
            online: false,
            installed: true
        })

        const preview = findChild(page, "selectedPreviewImage")
        verify(preview !== null)
        compare(preview.source.toString(), "file:///tmp/guardian.jpg")
        compare(page.selectedPreviewPath, "/tmp/guardian.jpg")
        const state = findChild(page, "selectionStateLabel")
        verify(state !== null)
        compare(state.text, "Selected — not applied yet")
        page.appliedWorkshopId = "2080115941"
        compare(state.text, "Currently applied")
    }

    function test_scene_selection_keeps_last_real_source_until_render_is_ready() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.cfg_WallpaperType = "video"
        page.cfg_MediaPath = "/tmp/last-real.mp4"
        page.cfg_WallpaperSource = "/tmp/last-real.mp4+video"
        const scene = {
            workshopId: "9999999998",
            title: "Pending scene",
            kind: "scene",
            renderKind: "scene",
            support: "Native scene",
            folder: "/tmp/nonexistent-scene-project",
            preview: "file:///tmp/preview.jpg",
            media: "/tmp/nonexistent-scene-project/scene.json"
        }

        page.chooseWallpaper(scene)

        compare(page.cfg_WallpaperType, "video")
        compare(page.cfg_MediaPath, "/tmp/last-real.mp4")
        compare(page.cfg_WallpaperSource, "/tmp/last-real.mp4+video")
        compare(page.sceneChecking, false)
        compare(page.sceneNeedsRestage, true)
        page.applyProjectInfo({}, "")
        const applyButton = findChild(page, "primaryApplyButton")
        verify(applyButton !== null)
        verify(applyButton.enabled)
    }

    function test_online_workshop_controls_are_present() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})

        verify(findChild(page, "workshopSourcePicker") !== null)
        verify(findChild(page, "workshopSortPicker") !== null)
        verify(findChild(page, "workshopPreviousPage") !== null)
        verify(findChild(page, "workshopNextPage") !== null)
    }

    function test_live_catalog_refresh_preserves_cached_preview_metadata() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        verify(page !== null)
        page.localCatalog = [{
            title: "Cached", workshopId: "111", kind: "video", renderKind: "video",
            support: "Native video", folder: "/old/111", preview: "file:///old.jpg",
            media: "/old.mp4", sizeBytes: 999, previewWidth: 1920, previewHeight: 1080
        }]

        var merged = page.mergeLocalCatalogItems([{
            title: "Fresh", workshopId: "111", kind: "video", renderKind: "video",
            support: "Native video", folder: "/new/111", preview: "file:///new.jpg",
            media: "/new.mp4", sizeBytes: 0, previewWidth: 0, previewHeight: 0
        }, {
            title: "New item", workshopId: "222", kind: "scene", renderKind: "scene",
            support: "Animated scene", folder: "/new/222", preview: "file:///new2.jpg",
            media: "/new/222/scene.json", sizeBytes: 0, previewWidth: 0, previewHeight: 0
        }])

        compare(merged.length, 2)
        compare(merged[0].title, "Fresh")
        compare(merged[0].media, "/new.mp4")
        compare(merged[0].sizeBytes, 999)
        compare(merged[0].previewWidth, 1920)
        compare(merged[1].workshopId, "222")
    }

    function test_online_normalization_preserves_workshop_metadata() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const item = page.normalizedCatalogItem({
            workshopId: "123", title: "Remote", author: "Artist",
            description: "Animated city", tags: ["Scene", "4K"],
            subscriptions: 900, views: 1200, rating: 4.5, updatedEpoch: 1700000000,
            sizeBytes: 2048, installed: false
        }, true)

        compare(item.description, "Animated city")
        compare(item.tagsText, "Scene • 4K")
        compare(item.subscriptions, 900)
        compare(item.views, 1200)
        compare(item.rating, 4.5)
    }

    function test_uninstalled_online_item_never_stages_its_preview() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.cfg_WallpaperType = "video"
        page.cfg_MediaPath = "/tmp/last-real.mp4"
        page.cfg_WallpaperSource = "/tmp/last-real.mp4+video"

        page.selectGalleryItem({
            title: "Remote wallpaper", workshopId: "3792870366", kind: "workshop",
            renderKind: "", support: "Available on Steam", folder: "",
            preview: "https://images.example/preview.jpg", media: "", sizeBytes: 0,
            previewWidth: 0, previewHeight: 0, online: true, installed: false,
            author: "Artist", workshopUrl: "https://steamcommunity.com/sharedfiles/filedetails/?id=3792870366"
        })

        compare(page.selectedItem.workshopId, "3792870366")
        compare(page.cfg_WallpaperType, "video")
        compare(page.cfg_MediaPath, "/tmp/last-real.mp4")
        compare(page.cfg_WallpaperSource, "/tmp/last-real.mp4+video")
        compare(page.selectedSourceReady, false)
        verify(page.applyStatus.indexOf("Download") >= 0)
        compare(findChild(page, "primaryApplyButton").enabled, false)
    }

    function test_failed_scene_render_never_commits_thumbnail() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const scene = {
            workshopId: "9999999997",
            title: "Broken scene",
            kind: "scene",
            renderKind: "scene",
            support: "Native scene",
            folder: "/tmp/broken-scene-project",
            preview: "file:///tmp/preview.jpg",
            media: "/tmp/broken-scene-project/scene.json"
        }
        page.selectionGeneration = 12
        page.selectedItem = scene
        page.cfg_WallpaperType = "video"
        page.cfg_MediaPath = "/tmp/last-real.mp4"
        page.cfg_WallpaperSource = "/tmp/last-real.mp4+video"
        page.applyAfterSceneCheck = true

        page.finishSceneFallback(12, scene, "renderer failed", {ok: false})

        compare(page.cfg_WallpaperType, "video")
        compare(page.cfg_MediaPath, "/tmp/last-real.mp4")
        compare(page.cfg_WallpaperSource, "/tmp/last-real.mp4+video")
        compare(page.applyAfterSceneCheck, false)
        compare(page.applyBlocked, true)
        compare(page.applyStatus, "No safely prepared scene is available • Previous wallpaper kept")
        compare(dialog.applyCount, 0)
    }

    function test_cancelled_scene_attempt_never_starts_static_fallback() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const scene = {
            workshopId: "9999999996", title: "Cancelable scene", kind: "scene",
            renderKind: "scene", support: "Rendered scene", folder: "/tmp/scene",
            preview: "file:///tmp/preview.jpg", media: "/tmp/scene/scene.json"
        }
        page.selectionGeneration = 20
        page.selectedItem = scene
        page.cfg_WallpaperType = "video"
        page.cfg_MediaPath = "/tmp/last-real.mp4"
        page.cfg_WallpaperSource = "/tmp/last-real.mp4+video"
        page.sceneChecking = true
        page.sceneNeedsRestage = false
        page.applyAfterSceneCheck = true
        page.activeSceneRenderId = "animated-20-1"

        page.handleAnimatedSceneResult(
            20, scene, "renderer", "/tmp/assets", "animated-20-1",
            {ok: false, cancelled: true, status: "scene render cancelled"}
        )

        compare(page.activeSceneRenderId, "")
        compare(page.sceneChecking, false)
        compare(page.sceneNeedsRestage, true)
        compare(page.applyAfterSceneCheck, false)
        compare(page.applyBlocked, false)
        compare(page.cfg_MediaPath, "/tmp/last-real.mp4")
        compare(page.cfg_WallpaperSource, "/tmp/last-real.mp4+video")
    }

    function test_stale_same_selection_attempt_cannot_publish() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        const scene = {
            workshopId: "9999999995", title: "Retried scene", kind: "scene",
            renderKind: "scene", support: "Rendered scene", folder: "/tmp/scene",
            preview: "file:///tmp/preview.jpg", media: "/tmp/scene/scene.json"
        }
        page.selectionGeneration = 21
        page.selectedItem = scene
        page.cfg_MediaPath = "/tmp/last-real.mp4"
        page.cfg_WallpaperSource = "/tmp/last-real.mp4+video"
        page.sceneChecking = true
        page.activeSceneRenderId = "animated-21-new"

        page.handleAnimatedSceneResult(
            21, scene, "renderer", "/tmp/assets", "animated-21-old",
            {ok: true, kind: "video", path: "/tmp/stale.mp4", width: 3840, height: 2160}
        )

        compare(page.activeSceneRenderId, "animated-21-new")
        compare(page.sceneChecking, true)
        compare(page.cfg_MediaPath, "/tmp/last-real.mp4")
        compare(page.cfg_WallpaperSource, "/tmp/last-real.mp4+video")
    }

    function test_scene_cache_input_change_invalidates_active_attempt() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        tryCompare(component, "status", Component.Ready)
        const page = component.createObject(testCase, {configDialog: dialog})
        page.selectedItem = {workshopId: "9999999994", kind: "scene"}
        page.activeSceneRenderId = "animated-22-1"
        page.sceneChecking = true
        page.sceneNeedsRestage = false
        page.applyAfterSceneCheck = true

        page.invalidateSceneRender("Scene settings changed")

        compare(page.activeSceneRenderId, "")
        compare(page.sceneChecking, false)
        compare(page.sceneNeedsRestage, true)
        compare(page.applyAfterSceneCheck, false)
        compare(page.selectedSourceReady, false)
        compare(page.applyStatus, "Scene settings changed")
    }

    function test_runtime_scene_path_uses_preflighted_native_animation_with_safe_fallback() {
        const mainRequest = new XMLHttpRequest()
        mainRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/main.qml"), false)
        mainRequest.send()
        const mainSource = mainRequest.responseText
        const configRequest = new XMLHttpRequest()
        configRequest.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        configRequest.send()
        const configSource = configRequest.responseText
        verify(configSource.indexOf("scenePreflightBridge.preflight_scene") >= 0)
        verify(configSource.indexOf('stageSelectedSource(generation, item, "scene", item.media') >= 0)
        verify(mainSource.indexOf('backendLoader.load("backend/Scene.qml"') >= 0)
        verify(mainSource.indexOf("function loadSceneAnimatedFallback") >= 0)
        verify(mainSource.indexOf("scene blocked; using preview") < 0)
    }

    function test_interactive_apply_uses_cached_scene_sources_only() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("cfg_DisableParallax, cfg_DisableParticles, renderId, true") >= 0)
        verify(source.indexOf("cfg_DisableParticles, renderId, true") >= 0)
    }

    function test_mpv_backend_uses_display_resample_for_smooth_mixed_refresh_playback() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/backend/Mpv.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf('player.setProperty("hwdec", "auto-safe")') >= 0)
        verify(source.indexOf('player.setProperty("video-sync", "display-resample")') >= 0)
        verify(source.indexOf('player.setProperty("interpolation", true)') >= 0)
        verify(source.indexOf('player.setProperty("tscale", "oversample")') >= 0)
        verify(source.indexOf('player.setProperty("loop-file", "inf")') >= 0)
        verify(source.indexOf('player.setProperty("keep-open", false)') >= 0)
    }

    function test_scene_fps_control_uses_supported_smooth_range() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(/from:\s*15\s*\n\s*to:\s*240/.test(source))
        verify(source.indexOf("to: 144") < 0)
    }

    function test_uncached_scene_capture_runs_past_the_old_restart_interval() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../plasma-plugin/contents/ui/Pyext.qml"), false)
        xhr.send()
        const source = xhr.responseText
        verify(source.indexOf("fps, 45, properties") >= 0)
        verify(source.indexOf("fps, 12, properties") < 0)
    }
}
