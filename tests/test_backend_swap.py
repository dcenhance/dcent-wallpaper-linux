"""Run the production backend handoff functions against owned items."""
import json
from pathlib import Path
import subprocess


def test_autopause_waits_for_asynchronous_backend():
    text = (Path(__file__).parents[1] / 'plasma-plugin/contents/ui/main.qml').read_text()
    start = text.index('    function pauseBackend()')
    end = text.index('    Component.onCompleted:', start)
    result = subprocess.run(['node', '-e', 'let background={ok:true}; let backendLoader={item:null};' + text[start:end] + 'autoPause();'], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_backend_retires_only_after_first_frame_or_timeout():
    text = (Path(__file__).parents[1] / 'plasma-plugin/contents/ui/main.qml').read_text()
    start = text.index('        function shutdownBackend(')
    end = text.index('        function load(url, properties)', start)
    functions = text[start:end]
    script = '''let retired = 0;
let retiredTarget = {visible:true, stopRenderer: () => {}, destroy: delay => {
 if (delay < 1000 || retiredTarget.visible) throw Error('renderer destroyed before stop/hide/drain');
 retired++;
}};
let retiringItem = retiredTarget;
let backendSwapTimeout = {stop: () => {}};
function changeMouseTarget() {}
''' + functions + '''
finishBackendSwap();
if (retired !== 1 || retiringItem !== null) throw Error('first frame did not retire previous renderer');
'''
    result = subprocess.run(['node', '-e', script], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_fractional_scale_video_uses_qt_multimedia_not_mpv():
    text = (Path(__file__).parents[1] / 'plasma-plugin/contents/ui/main.qml').read_text()
    assert 'readonly property bool fractionalScale' in text
    assert 'background.videoBackend == Common.VideoBackend.Mpv && background.hasLib && !background.fractionalScale' in text
