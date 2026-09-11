import QtQuick 2.0
import QtWebSockets 1.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

import "js/jsonrpc.mjs" as Jsonrpc

Item {
    id: root
    readonly property string file: "plasma/wallpapers/org.dcentwallpapers.plasma/contents/pyext.py"
    readonly property string source: {
        const sh = [
            `EXT=${file}`,
            `WKD="no_pyext_file_found"`,
            "[ -f /usr/share/$EXT ] && WKD=/usr/share/$EXT",
            "[ -f \"$HOME/.local/share/$EXT\" ] && WKD=\"$HOME/.local/share/$EXT\"",
            "[ -f \"$XDG_DATA_HOME/$EXT\" ] && WKD=\"$XDG_DATA_HOME/$EXT\"",
            `exec python3 "$WKD" "${ws_server.url}"`
        ].join("\n");
        return sh;
    }
    readonly property bool ok: ws_server.socket && ws_server.socket.status == WebSocket.Open

    property string _log
    readonly property string log: _log

    property var commands: []

    readonly property string version: _version

    property string _version: {
        if(ok) {
            ws_server.jrpc.send("version").then(res => {
                this._version = res.result
            });
        }
        return '-';
    }

    function set_login_wallpaper(preview) {
        return ws_server.jrpc.send("set_login_wallpaper", [preview], 720000).then(res => res.result);
    }
    function list_screens() {
        return ws_server.jrpc.send("list_screens", [], 15000).then(res => res.result);
    }
    function apply_to_screen(configuration, screenIndex) {
        return ws_server.jrpc.send("apply_to_screen", [configuration, screenIndex], 15000).then(res => res.result);
    }
    function apply_all_screens(configuration) {
        return ws_server.jrpc.send("apply_all_screens", [configuration], 15000).then(res => res.result);
    }
    function preflight_scene(source, assets) {
        return ws_server.jrpc.send("preflight_scene", [source, assets], 15000).then(res => res.result);
    }
    function audio_spectrum() {
        return ws_server.jrpc.send("audio_spectrum", [], 2500).then(res => res.result);
    }
    function cancel_scene_render(renderId) {
        return ws_server.jrpc.send("cancel_scene_render", [renderId || ""], 5000).then(res => res.result);
    }
    function render_scene_fallback(wallpaper, assets, mode, scaling, properties, disableParallax, disableParticles, renderId, cacheOnly) {
        return ws_server.jrpc.send(
            "render_scene_fallback",
            [wallpaper, assets, mode, scaling, properties || {}, Boolean(disableParallax), Boolean(disableParticles), renderId || "", Boolean(cacheOnly)],
            90000
        ).then(res => res.result);
    }
    function render_scene_video_fallback(wallpaper, assets, mode, scaling, fps, properties, disableParallax, disableParticles, renderId, cacheOnly) {
        return ws_server.jrpc.send(
            "render_scene_video_fallback",
            [wallpaper, assets, mode, scaling, fps, 45, properties || {}, Boolean(disableParallax), Boolean(disableParticles), renderId || "", Boolean(cacheOnly)],
            600000
        ).then(res => res.result);
    }
    function get_wallpaper_project(wallpaper, workshopId) {
        return ws_server.jrpc.send("get_wallpaper_project", [wallpaper, workshopId || ""], 15000).then(res => res.result);
    }
    function search_workshop(query, page, sort, kind, workshopRoot) {
        return ws_server.jrpc.send(
            "search_workshop", [query || "", page || 1, sort || "trend", kind || "all", workshopRoot || ""], 45000
        ).then(res => res.result);
    }
    function workshop_item_status(workshopId, workshopRoot) {
        return ws_server.jrpc.send(
            "workshop_item_status", [workshopId, workshopRoot || ""], 15000
        ).then(res => res.result);
    }
    function workshop_download(workshopId, steamLibrary) {
        return ws_server.jrpc.send(
            "workshop_download", [workshopId, steamLibrary || ""], 30000
        ).then(res => res.result);
    }
    function get_local_workshop_item(workshopId, workshopRoot) {
        return ws_server.jrpc.send(
            "get_local_workshop_item", [workshopId, workshopRoot || ""], 15000
        ).then(res => res.result);
    }
    function list_local_workshop_items(workshopRoot) {
        return ws_server.jrpc.send(
            "list_local_workshop_items", [workshopRoot || ""], 120000
        ).then(res => res.result);
    }
    function list_property_directory(path, fileType, maxFiles) {
        return ws_server.jrpc.send(
            "list_property_directory", [path || "", fileType || "", maxFiles || 512], 30000
        ).then(res => res.result);
    }
    function write_wallpaper_properties(workshopId, wallpaper, overrides) {
        return ws_server.jrpc.send(
            "write_wallpaper_properties", [workshopId, wallpaper, overrides || {}], 15000
        ).then(res => res.result);
    }
    function reset_wallpaper_properties(workshopId, wallpaper) {
        return ws_server.jrpc.send(
            "reset_wallpaper_properties", [workshopId, wallpaper], 15000
        ).then(res => res.result);
    }
    function readfile(path) {
        return ws_server.jrpc.send("readfile", [path]).then((el) => {
            return Qt.atob(el.result);
        });
    }
    function get_dir_size(path, depth=3) {
        return ws_server.jrpc.send("get_dir_size", [path, depth]).then(res => res.result);
    }
    function get_folder_list(path, opt={}) {
        return ws_server.jrpc.send("get_folder_list", [path, opt]).then(res => res.result);
    }
    function read_wallpaper_config(id) {
        return ws_server.jrpc.send("read_wallpaper_config", [id]).then(res => res.result);
    }
    function write_wallpaper_config(id, changed) {
        return ws_server.jrpc.send("write_wallpaper_config", [id, changed]);
    }
    function reset_wallpaper_config(id) {
        return ws_server.jrpc.send("reset_wallpaper_config", [id]);
    }
    function delete_wallpaper(path, workshopid) {
        return ws_server.jrpc.send("delete_wallpaper", [path, workshopid || ""]).then(res => res.result);
    }



    function _createTimer(callback) {
        const timer = Qt.createQmlObject("import QtQuick 2.0; Timer {}", root);
        const interval = 500;
        timer.interval = interval;
        timer.repeat = true;
        timer.triggered.connect(() => callback(500));
        timer.start();
        return timer;
    }

    WebSocketServer {
        id: ws_server
        listen: true
        property var socket: { status: WebSocket.Closed }
        property var backmsg: []
        property var jrpc: {
            jrpc = new Jsonrpc.Jsonrpc(sendStr.bind(this), _createTimer);
        }

        onClientConnected: function(webSocket) {
            console.error("----python helper connected----")
            this.socket = webSocket;
            webSocket.onTextMessageReceived.connect((message) => {
                ws_server.jrpc.receive(message);
            });
            webSocket.onStatusChanged.connect((status) => {
                if(status != WebSocket.Open) {
                    ws_server.jrpc.rejectUnfinished();
                    console.error("----python helper disconnected----")
                } else {
                    ws_server.dealBackmsg();
                }
            });
            this.dealBackmsg();
        }

        function dealBackmsg() {
            if(!ok) return;
            const m = backmsg;
            backmsg = [];
            m.forEach(el => {
                ws_server.socket.sendTextMessage(el);
            });
        }
        function sendStr(s) {
            if(!ok) {
                this.backmsg.push(s);
            } else {
                this.socket.sendTextMessage(s);
            }
        }
    }

    Plasma5Support.DataSource {
        engine: 'executable'
        connectedSources: [source]
        onNewData: {
            _log += "\n" + data.stderr;
            _log += "\n" + data.stdout;
            console.error(data.stderr);
            console.error(data.stdout);
        }
    }
}
