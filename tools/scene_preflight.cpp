#include <cstdio>
#include <cstdlib>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <QQuickWindow>
#include <QUrl>
#include <sys/resource.h>
#include <sys/prctl.h>

int main(int argc, char **argv) {
    const rlimit noCore {0, 0};
    setrlimit(RLIMIT_CORE, &noCore);
    // RLIMIT_CORE=0 alone does not suppress Linux's piped coredump handler.
    // Report a failed validator through the RPC, not a desktop crash dialog.
    prctl(PR_SET_DUMPABLE, 0);
    qputenv("KDE_DEBUG", "1");
    // Never create a compositor surface. Offscreen defaults to Qt's software
    // scenegraph, incompatible with SceneViewer's OpenGL/Vulkan interop.
    qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("QT_QUICK_BACKEND", "rhi");
    qputenv("QSG_RHI_BACKEND", "opengl");
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
    id: preflightRoot
    objectName: "preflightRoot"
    width: 1920
    height: 1080
    property bool rendered: false
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
            preflightRoot.rendered = true
            console.log("DCENT_PREFLIGHT_FIRST_FRAME")
            player.pause()
            // Let queued renderer/text updates drain before native destruction.
            shutdownTimer.start()
        }
    }

    Timer {
        id: shutdownTimer
        interval: 250
        onTriggered: Qt.quit()
    }
    Timer {
        // Cold Workshop shaders can take substantially longer than 3 seconds.
        interval: 20000
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
    // A timed-out load still owns compiler/audio workers. Destroying the QML
    // engine then races AudioAnalyzer::FeedPcm (reproduced with cold Akame).
    // This is a disposable validator: on failure let the OS reclaim its workers
    // rather than running unsafe native destructors. Never report it as safe.
    if (!rendered) {
        std::fflush(stderr);
        std::_Exit(66);
    }
    // Scenegraph-owned render workers emit signals on the QML SceneObject.
    // Stop/release those workers while the signal receiver is still alive.
    // A pause/drain alone does not establish this ownership order (Console 2.0).
    window->hide();
    window->releaseResources();
    QCoreApplication::processEvents();
    return 0; // Successful probes still exercise normal native teardown.
}
