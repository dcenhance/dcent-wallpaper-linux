#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <QUrl>
#include <sys/resource.h>

int main(int argc, char **argv) {
    const rlimit noCore {0, 0};
    setrlimit(RLIMIT_CORE, &noCore);
    QGuiApplication app(argc, argv);
    if (argc != 3) return 64;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("sceneSource", QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    engine.rootContext()->setContextProperty("assetsSource", QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])).toString());

    static const char qml[] = R"QML(
import QtQuick
import QtQuick.Window
import com.github.captsilver.wallpaperEngineKde 1.2

Window {
    objectName: "preflightRoot"
    width: 1920
    height: 1080
    opacity: 0.01
    x: 100000
    y: 100000
    visible: true
    color: "black"
    flags: Qt.Tool | Qt.FramelessWindowHint

    SceneViewer {
        id: player
        anchors.fill: parent
        source: sceneSource
        assets: assetsSource
        fps: 5
        muted: true
        fillMode: SceneViewer.ASPECTFIT
        Timer {
            interval: 250
            running: true
            repeat: false
            onTriggered: player.play()
        }
        onFirstFrame: {
            console.log("DCENT_PREFLIGHT_FIRST_FRAME")
            Qt.quit()
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
)QML";

    engine.loadData(qml, QUrl("file:///tmp/dcent-scene-preflight.qml"));
    if (engine.rootObjects().isEmpty()) return 65;
    app.exec();
    return 0;
}
