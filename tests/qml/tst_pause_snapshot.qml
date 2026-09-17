import QtQuick
import QtTest

/* The paused WebEngineView is replaced by a still frame. The grab result's own
   url uses Qt's internal "itemgrabber:" protocol, which Qt Quick's Image cannot
   load, so a snapshot must be persisted to a real file first. */
TestCase {
    id: testCase
    name: "PauseSnapshot"
    when: windowShown
    visible: true
    width: 320
    height: 200

    readonly property string snapshotPath: "/tmp/dcent-pause-snapshot-test.png"

    Rectangle {
        id: content
        anchors.fill: parent
        color: "#101820"

        Rectangle {
            x: 16
            y: 16
            width: 80
            height: 48
            color: "#ff8800"
        }
    }

    Image {
        id: probe
        cache: false
    }

    function test_grabbed_frame_is_loadable_through_a_file() {
        var saved = false
        content.grabToImage(function(result) {
            saved = result.saveToFile(testCase.snapshotPath)
        })
        tryVerify(function() { return saved }, 5000)

        probe.source = "file://" + testCase.snapshotPath
        tryCompare(probe, "status", Image.Ready, 5000)
        verify(probe.sourceSize.width >= content.width)
        verify(probe.sourceSize.height >= content.height)
    }

    function test_grab_result_url_is_an_internal_protocol() {
        var url = ""
        content.grabToImage(function(result) {
            url = String(result.url)
        })
        tryVerify(function() { return url !== "" }, 5000)
        compare(url.indexOf("itemgrabber:"), 0)
    }
}