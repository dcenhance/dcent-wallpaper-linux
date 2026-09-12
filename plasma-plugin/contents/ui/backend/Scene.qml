import QtQuick 2.5
import com.github.captsilver.wallpaperEngineKde 1.2
import ".."

Item{
    id: sceneItem
    anchors.fill: parent
    clip: true
    property alias source: player.source
    property string assets: "assets"
    property int displayMode: background.displayMode
    property string userPropsJson: background.userPropsJson
    property var volumeFade: Common.createVolumeFade(
        sceneItem,
        Qt.binding(function() { return background.mute ? 0 : background.volume; }),
        (volume) => { player.volume = volume / 100.0; }
    )

    onDisplayModeChanged: {
        if(displayMode == Common.DisplayMode.Scale)
            player.fillMode = SceneViewer.STRETCH;
        else if(displayMode == Common.DisplayMode.Crop)
            player.fillMode = SceneViewer.ASPECTCROP;
        else
            // Aspect (and any unset/unrecognised value) must fit the whole
            // scene. SceneViewer defaults to ASPECTCROP, which silently cuts
            // the composition when the config didn't resolve.
            player.fillMode = SceneViewer.ASPECTFIT;
    }

    SceneViewer {
        id: player
        x: background.spanCanvasX
        y: background.spanCanvasY
        width: background.spanCanvasWidth
        height: background.spanCanvasHeight
        fps: background.fps
        muted: background.mute
        speed: background.speed
        assets: sceneItem.assets
        userProperties: String(sceneItem.userPropsJson)
        systemAudioCapture: background.systemAudioCapture
        Component.onCompleted: {
            player.setAcceptMouse(true);
            player.setAcceptHover(true);
        }

        Connections {
            target: player
            function onFirstFrame() {
                background.sig_backendFirstFrame('scene');
            }
        }
    }

    Component.onCompleted: {
        background.nowBackend = 'scene';
        sceneItem.displayModeChanged();
    }
    function play() {
        volumeFade.start();
        player.play();
    }
    function pause() {
        volumeFade.stop();
        player.pause();
    }
    function stopRenderer() {
        try { volumeFade.stop(); } catch(e) {}
        try { player.pause(); } catch(e) {}
        try { sceneItem.visible = false; } catch(e) {}
    }

    function getMouseTarget() {
        return Qt.binding(function() { return player; })
    }
}
