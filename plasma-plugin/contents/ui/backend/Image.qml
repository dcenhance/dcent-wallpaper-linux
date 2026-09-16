import QtQuick 2.5
import ".."

Item {
    id: imageItem
    anchors.fill: parent
    clip: true

    property alias source: image.source
    property int displayMode: background.displayMode

    AnimatedImage {
        id: image
        x: background.spanEnabled ? background.spanCanvasX : 0
        y: background.spanEnabled ? background.spanCanvasY : 0
        width: background.spanEnabled ? background.spanCanvasWidth : imageItem.width
        height: background.spanEnabled ? background.spanCanvasHeight : imageItem.height
        asynchronous: true
        cache: true
        smooth: true
        playing: true
        fillMode: imageItem.displayMode === Common.DisplayMode.Scale
                  ? Image.Stretch
                  : imageItem.displayMode === Common.DisplayMode.Crop
                    ? Image.PreserveAspectCrop
                    : Image.PreserveAspectFit
        onStatusChanged: {
            if (status === Image.Ready)
                background.sig_backendFirstFrame("image")
        }
    }

    function play() { image.playing = true }
    function pause() { image.playing = false }
    function stopRenderer() { try { image.playing = false; } catch(e) {} try { imageItem.visible = false; } catch(e) {} }
    function getMouseTarget() { return null }
}
