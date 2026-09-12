#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QString>
#include <QUrl>
#include <cstdio>
#include <cstdlib>
#include <sys/resource.h>

int main(int argc, char **argv) {
    const rlimit noCore {0, 0};
    setrlimit(RLIMIT_CORE, &noCore);

    const bool hostMode = argc > 1 && QString::fromLatin1(argv[1]) == "--host";
    if ((!hostMode && argc != 3) || (hostMode && argc != 9)) return 64;

    const int sourceIndex = hostMode ? 2 : 1;
    const int assetsIndex = hostMode ? 3 : 2;
    const int width = hostMode ? qBound(320, QString::fromLocal8Bit(argv[4]).toInt(), 4096) : 1920;
    const int height = hostMode ? qBound(240, QString::fromLocal8Bit(argv[5]).toInt(), 2160) : 1080;
    const int fps = hostMode ? qBound(5, QString::fromLocal8Bit(argv[6]).toInt(), 240) : 5;
    const QString scaling = hostMode ? QString::fromLocal8Bit(argv[7]) : QStringLiteral("fit");
    const QString properties = hostMode ? QString::fromUtf8(argv[8]) : QStringLiteral("{}");

    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(
        "sceneSource", QUrl::fromLocalFile(QString::fromLocal8Bit(argv[sourceIndex])));
    engine.rootContext()->setContextProperty(
        "assetsSource", QUrl::fromLocalFile(QString::fromLocal8Bit(argv[assetsIndex])).toString());
    engine.rootContext()->setContextProperty("hostMode", hostMode);
    engine.rootContext()->setContextProperty("sceneWidth", width);
    engine.rootContext()->setContextProperty("sceneHeight", height);
    engine.rootContext()->setContextProperty("sceneFps", fps);
    engine.rootContext()->setContextProperty("captureScaling", scaling);
    engine.rootContext()->setContextProperty("sceneProperties", properties);
    // Cold Workshop shaders can need far longer than a warm cache. The caller
    // bounds the probe with its own subprocess timeout, so this only needs to be
    // an upper bound that never fires first on a healthy load.
    engine.rootContext()->setContextProperty("probeTimeoutMs", hostMode ? 300000 : 20000);

    static const char qml[] = R"QML(
import QtQuick
import QtQuick.Window
import com.github.captsilver.wallpaperEngineKde 1.2

Window {
    id: preflightRoot
    objectName: "preflightRoot"
    title: hostMode ? "Dcent Scene Capture" : "Dcent Scene Preflight"
    width: sceneWidth
    height: sceneHeight
    opacity: hostMode ? 1.0 : 0.01
    x: hostMode ? 16384 : 100000
    y: hostMode ? 0 : 100000
    visible: true
    color: "black"
    flags: Qt.Tool | Qt.FramelessWindowHint
    property bool rendered: false

    SceneViewer {
        id: player
        anchors.fill: parent
        source: sceneSource
        assets: assetsSource
        fps: sceneFps
        muted: true
        userProperties: sceneProperties
        fillMode: captureScaling === "stretch" ? SceneViewer.STRETCH
                  : captureScaling === "fill" ? SceneViewer.ASPECTCROP
                  : SceneViewer.ASPECTFIT
        Timer {
            interval: 250
            running: true
            repeat: false
            onTriggered: player.play()
        }
        onFirstFrame: {
            preflightRoot.rendered = true
            console.log("DCENT_PREFLIGHT_FIRST_FRAME")
            player.pause()
            // Let queued renderer/text updates drain before native teardown.
            shutdownTimer.start()
        }
    }

    Timer {
        id: shutdownTimer
        interval: 250
        onTriggered: Qt.quit()
    }

    Timer {
        interval: probeTimeoutMs
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
)QML";

    engine.loadData(qml, QUrl("file:///tmp/dcent-scene-preflight.qml"));
    if (engine.rootObjects().isEmpty()) return 65;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    window->setPersistentSceneGraph(false);
    window->setPersistentGraphics(false);
    app.exec();

    const bool rendered = engine.rootObjects().first()->property("rendered").toBool();
    std::fprintf(stderr, "%s\n", rendered ? "DCENT_PREFLIGHT_FIRST_FRAME" : "DCENT_PREFLIGHT_NO_FRAME");

    // A timed-out probe still owns compiler/audio workers. Destroying the QML
    // engine then races AudioAnalyzer::FeedPcm (reproduced on cold scenes), so a
    // no-frame result must never run native destructors: this is a disposable
    // validator, let the OS reclaim its workers and report the failure instead.
    if (!rendered) {
        std::fflush(stderr);
        std::_Exit(66);
    }

    // Scenegraph-owned render workers emit signals on the QML SceneObject.
    // Stop/release those workers while the signal receiver is still alive.
    window->hide();
    window->releaseResources();
    QCoreApplication::processEvents();
    return 0;
}
