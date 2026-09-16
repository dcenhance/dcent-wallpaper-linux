import QtQuick
import QtTest
import org.kde.kirigami as Kirigami

TestCase {
    id: testCase
    name: "KcmApplyLifecycle"
    when: windowShown
    visible: true
    width: 1100
    height: 700

    Component {
        id: hostComponent
        QtObject {
            property bool allScreens: false
            property var selectedScreen: ({name: "DP-1"})
            property var wallpaperConfiguration: null
            property int recursiveCalls: 0
            function applyWallpaper() { recursiveCalls++ }
        }
    }

    Component {
        id: serviceComponent
        QtObject {
            function reset_wallpaper_properties(id, folder) {
                return Promise.resolve({properties: [], userOverrides: {}, presetOverrides: {}})
            }
            property int updates: 0
            function update_active_settings(config, workshopId, folder, screen, all) {
                updates++; target = all ? "all" : screen; payload = config
                return Promise.resolve({ok: true})
            }
            property int preflights: 0
            property int commits: 0
            property string target: ""
            property var payload: null
            property string downloadRequested: ""
            property string statusRequested: ""
            property var resolveStatus
            property var resolvePreflight
            function workshop_download(id, library) {
                downloadRequested = id
                return Promise.resolve({ok: true, started: true})
            }
            function workshop_item_status(id, root) {
                statusRequested = id
                return new Promise(function(resolve) { resolveStatus = resolve })
            }
            function list_local_workshop_items(root) {
                return Promise.resolve({ok: true, items: []})
            }
            function preflight_scene(source, assets) {
                preflights++
                return new Promise(function(resolve) { resolvePreflight = resolve })
            }
            function apply_to_screen(config, screen) {
                commits++; target = screen; payload = config
                return Promise.resolve({ok: true})
            }
            function apply_all_screens(config) {
                commits++; target = "all"; payload = config
                return Promise.resolve({ok: true})
            }
        }
    }

    function test_scene_is_prepared_before_kde_apply_and_never_custom_committed() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        const item = {title: "Scene", workshopId: "42", kind: "scene", media: "/scene/scene.json", folder: "/scene", preview: ""}
        page.selectedItem = item
        page.selectionGeneration = 1
        page.sceneNeedsRestage = true
        page.cfg_WallpaperSource = "/previous.mp4+video"
        page.prepareNativeScene(1, item)
        tryCompare(service, "preflights", 1)
        compare(service.commits, 0)
        compare(page.cfg_WallpaperSource, "/previous.mp4+video")
        service.resolvePreflight({safe: true})
        tryCompare(page, "selectedSourceReady", true)
        compare(page.cfg_WallpaperSource, "/scene/scene.json+scene")
        page.saveConfig()
        wait(30)
        compare(service.commits, 0)
        compare(host.recursiveCalls, 0)
        compare(page.appliedWorkshopId, "42")
    }

    function test_unknown_screen_never_recurses_into_host_save() {
        const host = createTemporaryObject(hostComponent, testCase, {selectedScreen: null})
        const page = pageFor(host)
        page.selectedItem = {workshopId: "42"}
        page.selectionGeneration = 1
        page.stageSelectedSource(1, {workshopId: "42", folder: "/scene", preview: ""}, "video", "/video.mp4", "")
        page.saveConfig()
        wait(30)
        compare(host.recursiveCalls, 0)
    }

    function test_scene_preparation_marks_kde_dirty() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        let changes = 0
        page.configurationChanged.connect(function() { changes++ })
        const item = {title: "Scene", workshopId: "42", kind: "scene", media: "/scene/scene.json", folder: "/scene", preview: ""}
        page.selectedItem = item
        page.selectionGeneration = 1
        page.prepareNativeScene(1, item)
        tryCompare(service, "preflights", 1)
        service.resolvePreflight({safe: true})
        tryVerify(function() { return changes > 0 })
        compare(page.selectedSourceReady, true)
    }

    function test_cancelled_native_preflight_cannot_publish_or_apply() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        const item = {title: "Scene", workshopId: "42", kind: "scene", media: "/scene/scene.json", folder: "/scene", preview: ""}
        page.selectedItem = item
        page.selectionGeneration = 1
        page.sceneNeedsRestage = true
        page.cfg_WallpaperSource = "/previous.mp4+video"
        page.prepareNativeScene(1, item)
        tryCompare(service, "preflights", 1)
        page.cancelActiveSceneRender()
        service.resolvePreflight({safe: true})
        wait(30)
        compare(page.cfg_WallpaperSource, "/previous.mp4+video")
        compare(service.commits, 0)
    }

    function test_clean_details_use_kde_apply_and_disclose_advanced_options() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        compare(findChild(page, "quickApplyButton"), null)
        compare(findChild(page, "primaryApplyButton"), null)
        compare(findChild(page, "configureHeading"), null)
        compare(findChild(page, "overviewStateMessage"), null)
        const advanced = findChild(page, "advancedOptions")
        const toggle = findChild(page, "advancedToggle")
        verify(advanced !== null)
        verify(toggle !== null)
        compare(advanced.visible, false)
        toggle.clicked()
        compare(advanced.visible, true)
        const preview = findChild(page, "selectedPreviewImage")
        wait(50) // Let the layout settle after the disclosure changes.
        verify(preview.parent.height >= 140)
        verify(preview.parent.height <= 190)
        compare(page.catalogMetadata({kind: "scene", sizeBytes: 0}), "Scene")
        compare(page.catalogMetadata({kind: "video", sizeBytes: 512}), "Video • <1 MB")
    }

    function test_screen_change_during_preflight_never_applies_to_new_screen() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        const item = {title: "Scene", workshopId: "42", kind: "scene", media: "/scene/scene.json", folder: "/scene", preview: ""}
        page.selectedItem = item
        page.selectionGeneration = 1
        page.sceneNeedsRestage = true
        page.cfg_WallpaperSource = "/previous.mp4+video"
        page.prepareNativeScene(1, item)
        tryCompare(service, "preflights", 1)
        host.selectedScreen = {name: "HDMI-A-1"}
        service.resolvePreflight({safe: true})
        wait(30)
        compare(page.cfg_WallpaperSource, "/previous.mp4+video")
        compare(service.commits, 0)
    }

    function test_workshop_download_stays_owned_by_requested_item() {
        const page = pageFor(createTemporaryObject(hostComponent, testCase))
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        const itemA = {title: "A", workshopId: "101", kind: "video", renderKind: "video", online: true, installed: false, preview: "", folder: "", media: ""}
        const itemB = {title: "B", workshopId: "202", kind: "video", renderKind: "video", online: true, installed: false, preview: "", folder: "", media: ""}
        page.selectGalleryItem(itemA, false)
        const ownerGeneration = page.selectionGeneration
        page.openSelectedWorkshopItem()
        tryCompare(service, "downloadRequested", "101")
        compare(page.pendingWorkshopId, "101")
        compare(page.pendingWorkshopSelectionGeneration, ownerGeneration)

        page.selectGalleryItem(itemB, false)
        page.checkSelectedWorkshopInstall()
        tryCompare(service, "statusRequested", "101")
        service.resolveStatus({ok: true, installed: true})
        tryCompare(page, "pendingWorkshopId", "")
        compare(page.selectedItem.workshopId, "202")
        compare(page.selectedSourceReady, false)
        verify(page.onlineStatus.indexOf("available in Library") >= 0)
    }

    function test_catalog_filters_use_exact_tags_ratings_and_resolution() {
        const page = pageFor(createTemporaryObject(hostComponent, testCase))
        page.localCatalog = [
            {title: "Game 4K", workshopId: "1", kind: "scene", tags: ["Game", "3840 x 2160"], contentRating: "Everyone", folder: "/1"},
            {title: "Endgame portrait", workshopId: "2", kind: "scene", tags: ["Endgame", "1920 x 3840"], contentRating: "Mature", folder: "/2"},
            {title: "Unknown", workshopId: "3", kind: "web", tags: [], folder: "/3"}
        ]
        page.filterTag = "game"
        page.filterResolution = "3840x2160"
        page.filterRating = "everyone"
        page.rebuildCatalog()
        compare(findChild(page, "wallpaperGrid").count, 1)
        page.filterResolution = "1920x3840"
        page.rebuildCatalog()
        compare(findChild(page, "wallpaperGrid").count, 0, "Portrait must not match landscape 4K")
        page.filterTag = "endgame"
        page.filterRating = "mature"
        page.rebuildCatalog()
        compare(findChild(page, "wallpaperGrid").count, 1, "Exact tag match keeps Endgame separate from Game")
    }

    function test_dark_cards_are_darker_than_page_surface() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        page.Kirigami.Theme.inherit = false
        page.Kirigami.Theme.backgroundColor = Qt.rgba(0.2, 0.2, 0.2, 1)
        page.Kirigami.Theme.alternateBackgroundColor = Qt.rgba(0.3, 0.3, 0.3, 1)
        const bg = page.appSurface
        const card = page.cardSurface
        verify((card.r + card.g + card.b) / 3 < 0.15)
        verify(card.r + card.g + card.b < bg.r + bg.g + bg.b)
        page.Kirigami.Theme.backgroundColor = Qt.rgba(0.95, 0.95, 0.95, 1)
        page.Kirigami.Theme.alternateBackgroundColor = Qt.rgba(0.9, 0.9, 0.9, 1)
        verify(!page.darkPalette)
        compare(page.cardSurface, page.Kirigami.Theme.alternateBackgroundColor)
    }

    function test_gallery_wheel_uses_moderate_fixed_notches_and_clamps() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        page.height = 1600
        page.inspectorCollapsed = true
        page.localCatalogGeneration++
        let items = []
        for (let i = 0; i < 100; i++)
            items.push({title: "Wallpaper " + i, workshopId: String(i), kind: "video", folder: "/tmp/" + i, preview: "", media: "", renderKind: "video"})
        page.localCatalog = items
        page.rebuildCatalog()
        const grid = findChild(page, "wallpaperGrid")
        tryCompare(grid, "count", 100)
        wait(50)
        mouseWheel(grid, 80, 80, 0, -120)
        compare(grid.contentY, 72, "One notch must not jump whole rows or scale with window height")
        compare(page.propertiesLoading, false)
        mouseWheel(grid, 80, 80, 0, -60)
        compare(grid.contentY, 108, "High-resolution angle events preserve fractional notches")
        mouseWheel(grid, 80, 80, 0, -120000)
        compare(grid.contentY, Math.max(0, grid.contentHeight - grid.height))
        mouseWheel(grid, 80, 80, 0, 120000)
        compare(grid.contentY, 0)
    }

    function test_settings_wheel_travels_without_scrolling_gallery() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        page.advancedExpanded = true
        const settings = findChild(page, "settingsScroll")
        verify(settings !== null)
        wait(50)
        mouseWheel(settings, 60, 60, 0, -120)
        compare(settings.contentItem.contentY, 48, "Settings move three readable lines, exactly once")
        compare(findChild(page, "wallpaperGrid").contentY, 0)
        mouseWheel(settings, 60, 60, 0, -120000)
        compare(settings.contentItem.contentY, Math.max(0, settings.contentItem.contentHeight - settings.contentItem.height))
        mouseWheel(settings, 60, 60, 0, 120000)
        compare(settings.contentItem.contentY, 0)
        compare(page.wheelTravel(12, 0, 900), 12)
        compare(page.wheelTravel(-8, 120, 900), -8)
    }

    function test_wallpaper_controls_collapse_without_hiding_provider_settings() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        page.selectedItem = {title: "Test", workshopId: "42", kind: "web"}
        page.applyProjectInfo({properties: [{name: "clock", label: "Show clock", type: "bool", editable: true, value: true, default: true, presetValue: true}]}, "")
        const list = findChild(page, "wallpaperEnginePropertyList")
        const toggle = findChild(page, "wallpaperOptionsToggle")
        verify(toggle !== null)
        verify(list.visible)
        toggle.clicked()
        verify(!list.visible)
        verify(findChild(page, "dcentGeneralSettingsSection").visible)
        toggle.clicked()
        verify(list.visible)
    }

    function test_compact_inspector_geometry_data() {
        return [{tag: "narrow", pageWidth: 900}, {tag: "normal", pageWidth: 1100}, {tag: "wide", pageWidth: 1600}]
    }

    function test_compact_inspector_geometry(data) {
        const page = pageFor(createTemporaryObject(hostComponent, testCase))
        page.width = data.pageWidth
        wait(50)
        const panel = findChild(page, "inspectorPanel")
        verify(panel.width >= 300, "Sidebar must remain readable: " + panel.width)
        verify(panel.width <= 340, "Sidebar should leave room for the library: " + panel.width)
        const preview = findChild(page, "selectedPreviewImage").parent
        verify(preview.height >= 140 && preview.height <= 190, "Responsive preview height: " + preview.height)
        verify(Math.abs(preview.height - preview.width * 9 / 16) < 2,
               "Preview keeps a compact 16:9 frame: " + preview.width + "×" + preview.height)
        const provider = findChild(page, "dcentGeneralSettingsSection")
        verify(provider.width <= panel.width)
        verify(provider.spacing <= 6)
    }

    function test_dense_property_controls_keep_long_labels_and_sliders_usable() {
        const page = pageFor(createTemporaryObject(hostComponent, testCase))
        page.width = 900
        page.selectedItem = {title: "Long-label regression", workshopId: "42", kind: "web", preview: ""}
        page.applyProjectInfo({properties: [
            {name: "clock", label: "Show the clock and its detailed background decoration", type: "bool", editable: true, default: true, value: true},
            {name: "speed", label: "Animation speed", type: "slider", editable: true, default: 1, value: 1, min: 0, max: 10, step: 0.1, allowTextEntry: true}
        ]}, "")
        wait(80)
        const list = findChild(page, "wallpaperEnginePropertyList")
        const check = findChild(list, "wallpaperBooleanEditor")
        verify(check !== null, "Boolean editor must expose its bounded label")
        verify(check.width <= list.width)
        verify(check.contentItem.lineCount > 1, "Long labels wrap rather than clip")
        const slider = findChild(list.itemAtIndex(1), "wallpaperSliderEditor")
        verify(slider.width >= 140, "Slider remains usable beside numeric entry: " + slider.width)
        verify(list.spacing <= 6)
        verify(findChild(page, "wallpaperSettingsSection").spacing <= 6)
    }

    function pageFor(host) {
        const component = Qt.createComponent(Qt.resolvedUrl("../../plasma-plugin/contents/ui/config.qml"))
        compare(component.status, Component.Ready, component.errorString())
        const page = createTemporaryObject(component, testCase, {configDialog: host, width: 1100, height: 700, localCatalog: []})
        verify(page !== null)
        return page
    }

    function test_host_populates_configuration_after_component_completed() {
        const page = pageFor(createTemporaryObject(hostComponent, testCase))
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        // KDE assigns cfg_* from its Loader.onLoaded, after Component.onCompleted.
        page.cfg_WallpaperWorkShopId = "42"
        page.cfg_WallpaperPath = "/scene"
        page.cfg_MediaPath = "/scene/scene.json"
        page.cfg_WallpaperSource = "/scene/scene.json+scene"
        page.localCatalog = [{title: "Scene", workshopId: "42", folder: "/scene", media: "/scene/scene.json", preview: "", kind: "scene"}]
        page.rebuildCatalog()
        tryCompare(page, "appliedWorkshopId", "42")
        compare(page.applyStatus, "Active wallpaper")
        page.cfg_Fps = 61
        page.settingsEdited()
        tryCompare(service, "updates", 1)
    }

    function test_active_settings_coalesce_without_apply_or_preflight_data() {
        return [{tag: "screen", all: false}, {tag: "all", all: true}]
    }

    function test_active_settings_coalesce_without_apply_or_preflight(data) {
        const host = createTemporaryObject(hostComponent, testCase, {allScreens: data.all})
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        page.selectedItem = {workshopId: "42", folder: "/scene", kind: "scene"}
        page.appliedWorkshopId = "42"
        page.cfg_WallpaperSource = "/scene/scene.json+scene"
        page.cfg_Fps = 60
        page.settingsEdited()
        page.cfg_Fps = 90
        page.settingsEdited()
        tryCompare(service, "updates", 1)
        compare(service.payload.Fps, 90)
        compare(service.target, data.all ? "all" : "DP-1")
        compare(service.preflights, 0)
        compare(service.commits, 0)
        compare(page.cfg_WallpaperSource, "/scene/scene.json+scene")
    }

    function test_native_scene_unsupported_switches_are_disabled() {
        const page = pageFor(createTemporaryObject(hostComponent, testCase))
        page.selectedItem = {workshopId: "42", folder: "/scene", kind: "scene"}
        page.cfg_WallpaperSource = "/scene/scene.json+scene"
        page.advancedExpanded = true
        function findText(item, text) {
            if (item.text === text) return item
            for (let child of item.children || []) {
                const found = findText(child, text)
                if (found) return found
            }
            return null
        }
        const parallax = findText(page, "Disable scene parallax")
        const particles = findText(page, "Disable scene particles")
        verify(parallax !== null)
        verify(particles !== null)
        compare(parallax.enabled, false)
        compare(particles.enabled, false)
    }

    function test_reset_active_properties_updates_without_apply() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        page.selectedItem = {workshopId: "42", folder: "/scene", kind: "scene", title: "Scene", preview: ""}
        page.appliedWorkshopId = "42"
        page.cfg_WallpaperSource = "/scene/scene.json+scene"
        page.resetWallpaperProperties()
        tryCompare(service, "updates", 1)
        compare(service.payload.PropertyOverrides, "")
        compare(service.preflights, 0)
        compare(page.sceneNeedsRestage, false)
    }

    function test_pending_selection_settings_do_not_activate_it() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        const service = createTemporaryObject(serviceComponent, testCase)
        page.transactionBridge = service
        page.appliedWorkshopId = "old"
        page.selectedItem = {workshopId: "new", folder: "/new", kind: "video"}
        page.cfg_WallpaperSource = "/new/video.mp4+video"
        page.settingsEdited()
        wait(400)
        compare(service.updates, 0)
        compare(service.commits, 0)
        compare(page.cfg_WallpaperSource, "/new/video.mp4+video")
    }

    function test_outer_apply_never_publishes_unprepared_scene() {
        const host = createTemporaryObject(hostComponent, testCase)
        const page = pageFor(host)
        page.cfg_WallpaperSource = "/previous.mp4+video"
        page.selectedItem = {title: "Scene", workshopId: "42", kind: "scene", media: "/scene/scene.json", folder: "/scene", preview: "file:///preview.jpg"}
        page.selectionGeneration = 1
        page.sceneNeedsRestage = true
        page.propertiesLoading = true
        page.saveConfig()
        compare(page.applyAfterSceneCheck, false)
        compare(page.cfg_WallpaperSource, "/previous.mp4+video")
        verify(page.applyStatus.indexOf("Still preparing") >= 0)
        compare(host.recursiveCalls, 0)
    }
}
