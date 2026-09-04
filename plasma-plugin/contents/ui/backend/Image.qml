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
        x: background.spanCanvasX
        y: background.spanCanvasY
        width: background.spanCanvasWidth
        height: background.spanCanvasHeight
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
    function getMouseTarget() { return null }
}
