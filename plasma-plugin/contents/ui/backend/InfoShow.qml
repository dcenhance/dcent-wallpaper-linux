import QtQuick 2.5
import QtQuick.Layouts 1.2

Item {
    id: infoItem
    anchors.fill: parent

    property string info: "error"
    property string type: "unknown"
    property string wid: "unknown"
    property string source

    Rectangle {
        anchors.fill: parent
        color: "#060606"
    }

    GridLayout {
        id: configRow
        columns: 1
        rows: 1
        anchors.fill: parent

        Text {
            Layout.alignment: Qt.AlignCenter
            Layout.fillWidth: true
            Layout.preferredWidth: infoItem.width * 0.75
            text: [
                `Shop id: ${infoItem.wid}`,
                `Type: ${infoItem.type}`,
                `Message: ${infoItem.info}`
            ].join("\n");
            color: "#ffd54f"
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            font.pointSize: Math.max(12, Math.min(18, infoItem.width / 50.0))
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Component.onCompleted:{
        background.nowBackend = "InfoShow";
    }

    function play(){}

    function pause(){}
    function stopRenderer() { try { infoItem.visible = false; } catch(e) {} }
    function getMouseTarget() {}
}
