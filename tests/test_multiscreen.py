from __future__ import annotations

import asyncio
import importlib.util
import json
import sys
import threading
import time
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "plasma-plugin" / "contents" / "pyext.py"
spec = importlib.util.spec_from_file_location("dcent_pyext", MODULE_PATH)
pyext = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pyext)


def test_background_rpc_does_not_block_fast_requests():
    rpc = pyext.Jsonrpc()
    started = threading.Event()
    release = threading.Event()

    @rpc.add_method
    def render_scene_video_fallback():
        started.set()
        release.wait(timeout=2)
        return "rendered"

    @rpc.add_method
    def get_wallpaper_project():
        return "metadata"

    async def exercise():
        slow = asyncio.create_task(rpc.handle_async(json.dumps({"id": 1, "method": "render_scene_video_fallback"})))
        assert await asyncio.to_thread(started.wait, 1)
        fast_response = await asyncio.wait_for(
            rpc.handle_async(json.dumps({"id": 2, "method": "get_wallpaper_project"})),
            timeout=0.25,
        )
        release.set()
        slow_response = await asyncio.wait_for(slow, timeout=1)
        return json.loads(fast_response), json.loads(slow_response)

    fast, slow = asyncio.run(exercise())
    assert fast == {"id": 2, "result": "metadata"}
    assert slow == {"id": 1, "result": "rendered"}


def test_scene_render_coordinator_cancels_stale_processes():
    class FakeProcess:
        def __init__(self):
            self.returncode = None
            self.terminate_count = 0

        def poll(self):
            return self.returncode

        def terminate(self):
            self.terminate_count += 1
            self.returncode = -15

    coordinator = pyext.SceneRenderCoordinator()
    stale = coordinator.begin()
    stale_process = FakeProcess()
    stale.track(stale_process)

    current = coordinator.begin()

    assert stale.cancelled is True
    assert stale_process.terminate_count == 1
    assert current.cancelled is False
    assert coordinator.cancel() is True
    assert current.cancelled is True
    coordinator.finish(stale)
    assert coordinator.active is current
    coordinator.finish(current)
    assert coordinator.active is None


def test_cancel_scene_render_rpc_cancels_the_active_job():
    job = pyext.SCENE_RENDERS.begin()
    try:
        result = pyext.cancel_scene_render()
        assert result == {"ok": True, "cancelled": True}
        assert job.cancelled is True
    finally:
        pyext.SCENE_RENDERS.finish(job)


def test_targeted_scene_cancellation_is_race_safe():
    coordinator = pyext.SceneRenderCoordinator()

    assert coordinator.cancel("queued") is True
    queued = coordinator.begin("queued")
    assert queued.cancelled is True

    current = coordinator.begin("current")
    assert current.cancelled is False
    coordinator.finish("queued", queued)
    assert coordinator.active is current

    assert coordinator.cancel("old") is True
    assert current.cancelled is False
    assert coordinator.cancel("current") is True
    assert current.cancelled is True
    coordinator.finish("current", current)
    assert coordinator.active is None


def test_cancellable_process_reaps_the_tracked_child():
    job = pyext.SceneRenderJob("capture-test")
    outcome = []

    def run_child():
        try:
            pyext.run_cancellable_process(
                job,
                [sys.executable, "-c", "import time; time.sleep(30)"],
                timeout=60,
                capture_output=True,
                text=True,
            )
        except BaseException as error:
            outcome.append(error)

    worker = threading.Thread(target=run_child)
    started = time.monotonic()
    worker.start()
    while job.process_count == 0 and time.monotonic() - started < 2:
        time.sleep(0.01)

    assert job.process_count == 1
    job.cancel()
    worker.join(timeout=2)

    assert worker.is_alive() is False
    assert len(outcome) == 1
    assert isinstance(outcome[0], pyext.SceneRenderCancelled)
    assert job.process_count == 0


def test_parse_output_bounds_handles_negative_geometry_and_scaling():
    output = """
Output: 1 DP-2 uuid
\x1b[01;33m    Geometry: \x1b[0;0m-2560,0 2560x1440
    Scale: 1.5
Output: 2 DP-1 uuid
\x1b[01;33m    Geometry: \x1b[0;0m0,0 2560x1440
    Scale: 1
"""
    assert pyext.parse_output_bounds(output) == {
        "VirtualDesktopX": -2560,
        "VirtualDesktopY": 0,
        "VirtualDesktopWidth": 5120,
        "VirtualDesktopHeight": 1440,
    }
    assert pyext.parse_outputs(output) == [
        {"index": 0, "name": "DP-2", "x": -2560, "y": 0, "width": 2560, "height": 1440, "scale": 1.5},
        {"index": 1, "name": "DP-1", "x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.0},
    ]
    outputs = pyext.parse_outputs(output)
    assert pyext.choose_scene_fallback_resolution(outputs, "mirror") == (3840, 2160)
    assert pyext.choose_scene_fallback_resolution(outputs, "span") == (7680, 2160)
    assert pyext.bound_video_decoder_resolution(7680, 2160) == (4096, 1152)
    assert pyext.choose_scene_fallback_resolution(outputs, "mirror", 60) == (2560, 1440)
    high_width, high_height = pyext.choose_scene_fallback_resolution(outputs, "mirror", 240)
    assert high_width * high_height * 240 <= 250_000_000
    assert high_width < 2560 and high_height < 1440


def test_scene_fallback_command_uses_explicit_high_resolution_window(tmp_path):
    renderer = tmp_path / "linux-wallpaperengine"
    wallpaper = tmp_path / "431960" / "2904412422"
    assets = tmp_path / "wallpaper_engine" / "assets"
    screenshot = tmp_path / "fallback.png"
    command = pyext.build_scene_fallback_command(
        renderer, wallpaper, assets, screenshot, 3840, 2160, "fill"
    )
    assert command[0] == str(renderer)
    assert command[command.index("--window") + 1] == "-3920x0x3840x2160"
    assert command[command.index("--screenshot") + 1] == str(screenshot)
    assert command[command.index("--assets-dir") + 1] == str(assets)
    assert command[command.index("--scaling") + 1] == "fill"
    assert command[-1] == str(wallpaper)


def test_scene_video_renderer_command_is_windowed_and_noninteractive(tmp_path):
    renderer = tmp_path / "linux-wallpaperengine"
    wallpaper = tmp_path / "431960" / "2904412422"
    assets = tmp_path / "wallpaper_engine" / "assets"

    command = pyext.build_scene_video_renderer_command(
        renderer, wallpaper, assets, 3840, 2160, "fill", fps=240
    )

    assert command[0] == str(renderer)
    assert command[command.index("--window") + 1] == "-3920x0x3840x2160"
    assert command[command.index("--assets-dir") + 1] == str(assets)
    assert command[command.index("--scaling") + 1] == "fill"
    assert command[command.index("--fps") + 1] == "240"
    assert "--disable-mouse" in command
    assert "--no-fullscreen-pause" in command
    assert "--screenshot" not in command
    assert command[-1] == str(wallpaper)


def test_scene_video_smoothing_command_produces_exact_cfr(tmp_path):
    ffmpeg = tmp_path / "ffmpeg"
    captured = tmp_path / "captured.mp4"
    destination = tmp_path / "smoothed.mp4"

    command = pyext.build_scene_video_smoothing_command(
        ffmpeg, captured, destination, 60, "h264_nvenc", 12
    )

    assert command[0] == str(ffmpeg)
    assert command[command.index("-i") + 1] == str(captured)
    filter_graph = command[command.index("-filter_complex") + 1]
    assert "minterpolate=fps=60:mi_mode=blend" in filter_graph
    assert "xfade=transition=fade:duration=3" in filter_graph
    assert command[command.index("-fps_mode") + 1] == "cfr"
    assert command[command.index("-c:v") + 1] == "h264_nvenc"
    assert command[-1] == str(destination)


def test_scene_capture_duration_keeps_long_loop_requests():
    assert pyext.normalize_scene_capture_duration(45) == 45
    assert pyext.normalize_scene_capture_duration(999) == 180
    assert pyext.normalize_scene_capture_duration("invalid") == 45
    assert pyext.scene_loop_overlap(12) == 3
    assert pyext.scene_loop_overlap(45) == 3


def test_scene_fallback_cache_namespace_requires_seamless_v4():
    source = MODULE_PATH.read_text(encoding="utf-8")
    assert '"animated-v4"' in source
    assert '"animated-v3"' not in source


def test_video_frame_count_rejects_stuttery_high_fps_cache():
    assert pyext.video_frame_count_is_smooth(717, 11.95, 60) is True
    assert pyext.video_frame_count_is_smooth(495, 11.98, 60) is False
    assert pyext.video_frame_count_is_smooth(354, 12.0, 30) is True


def test_scene_video_capture_command_records_only_the_renderer_window(tmp_path):
    ffmpeg = tmp_path / "ffmpeg"
    destination = tmp_path / "fallback.mp4"

    command = pyext.build_scene_video_capture_command(
        ffmpeg, ":0", 71303175, destination, 3840, 2160, 30, 24, "h264_nvenc"
    )

    assert command[0] == str(ffmpeg)
    assert command[command.index("-window_id") + 1] == "71303175"
    assert command[command.index("-video_size") + 1] == "3840x2160"
    assert command[command.index("-framerate") + 1] == "30"
    assert command[command.index("-i") + 1] == ":0"
    assert command[command.index("-t") + 1] == "24"
    assert command[command.index("-c:v") + 1] == "h264_nvenc"
    assert "-an" in command
    assert command[-1] == str(destination)


def test_scene_video_fallback_rejects_non_scene_project(tmp_path):
    wallpaper = tmp_path / "wallpaper"
    assets = tmp_path / "assets"
    wallpaper.mkdir()
    assets.mkdir()
    (wallpaper / "project.json").write_text('{"type": "video"}')
    (wallpaper / "scene.pkg").write_bytes(b"packed")

    result = pyext.render_scene_video_fallback(str(wallpaper), str(assets))

    assert result["ok"] is False
    assert result["status"] == "animated fallback requires a packed scene"


def test_cache_only_scene_apply_never_starts_external_renderer(tmp_path, monkeypatch):
    home = tmp_path / "home"
    renderer = home / ".local" / "bin" / "linux-wallpaperengine"
    renderer.parent.mkdir(parents=True)
    renderer.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")
    renderer.chmod(0o755)
    wallpaper = tmp_path / "431960" / "1234567890"
    wallpaper.mkdir(parents=True)
    (wallpaper / "project.json").write_text(
        json.dumps({"title": "Scene", "type": "scene", "file": "scene.json"}),
        encoding="utf-8",
    )
    (wallpaper / "scene.pkg").write_bytes(b"packed")
    assets = tmp_path / "assets"
    assets.mkdir()
    monkeypatch.setattr(pyext.Path, "home", classmethod(lambda cls: home))
    monkeypatch.setattr(pyext, "_list_screens_for_render", lambda job: [])
    monkeypatch.setattr(
        pyext.subprocess,
        "Popen",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("renderer started")),
    )

    still = pyext._render_scene_fallback(str(wallpaper), str(assets), cache_only=True)
    video = pyext._render_scene_video_fallback(str(wallpaper), str(assets), cache_only=True)

    assert still == {"ok": False, "cacheMiss": True, "status": "no cached scene still is ready"}
    assert video == {"ok": False, "cacheMiss": True, "status": "no cached animated scene is ready"}


def test_run_plasma_script_retries_transient_dbus_failures(monkeypatch):
    calls = []

    class Result:
        def __init__(self, returncode, stdout="", stderr=""):
            self.returncode = returncode
            self.stdout = stdout
            self.stderr = stderr

    def fake_run(command, **kwargs):
        calls.append(command)
        if len(calls) == 1:
            return Result(1, "", "org.freedesktop.DBus.Error.NoReply")
        return Result(0, "\\n", "")

    monkeypatch.setattr(pyext.subprocess, "run", fake_run)
    result = pyext.run_plasma_script("var items = desktops();", attempts=2)
    assert result.returncode == 0
    assert len(calls) == 2


def test_apply_plasma_script_retries_until_readback_matches(monkeypatch):
    calls = []

    class Result:
        returncode = 0
        stdout = "\n"
        stderr = ""

    monkeypatch.setattr(pyext, "run_plasma_script", lambda script: calls.append(script) or Result())
    reads = iter([(False, {}), (True, {"wallpaperPlugin": "org.dcentwallpapers.plasma"})])
    monkeypatch.setattr(pyext, "wait_for_wallpaper_readback", lambda *args, **kwargs: next(reads))
    ok, result, readback = pyext.apply_plasma_script("var x = 1;", [0], {}, attempts=2)
    assert ok is True
    assert result.returncode == 0
    assert readback["wallpaperPlugin"] == "org.dcentwallpapers.plasma"
    assert len(calls) == 2


def test_apply_script_targets_one_selected_desktop_only():
    script = pyext.build_apply_screen_script(
        {
            "WallpaperSource": "/tmp/right.jpg+image",
            "WallpaperType": "image",
            "MultiScreenMode": "single",
            "UntrustedKey": "must-not-be-written",
        },
        1,
    )
    assert "if (desktop.screen !== 1) continue;" in script
    assert 'if (desktop.wallpaperPlugin !== "org.dcentwallpapers.plasma") continue;' in script
    assert 'desktop.writeConfig("VirtualDesktopWidth", 0);' in script
    assert 'desktop.writeConfig("WallpaperSource", "/tmp/right.jpg+image")' in script
    assert 'desktop.writeConfig("MultiScreenMode", "single")' in script
    assert script.count("desktop.reloadConfig();") == 2
    assert script.index('desktop.writeConfig("WallpaperSource", "/tmp/right.jpg+image")') < script.rindex("desktop.reloadConfig();")
    assert "UntrustedKey" not in script


def test_screen_target_accepts_kde_output_name_or_numeric_index():
    screens = [
        {"index": 0, "name": "DP-2"},
        {"index": 1, "name": "DP-1"},
    ]

    assert pyext.resolve_screen_target(screens, "DP-1") == screens[1]
    assert pyext.resolve_screen_target(screens, "0") == screens[0]
    assert pyext.resolve_screen_target(screens, 1) == screens[1]
    assert pyext.resolve_screen_target(screens, "missing") is None


def test_apply_script_targets_every_desktop_and_filters_keys():
    script = pyext.build_apply_all_script(
        {
            "WallpaperSource": "/tmp/a.jpg+image",
            "WallpaperType": "image",
            "MultiScreenMode": "span",
            "PropertyOverrides": '{"enabled":false}',
            "DisableParallax": True,
            "UntrustedKey": "must-not-be-written",
        }
    )
    assert "var items = desktops()" in script
    assert 'desktop.wallpaperPlugin = "org.dcentwallpapers.plasma"' in script
    assert 'desktop.writeConfig("WallpaperSource", "/tmp/a.jpg+image")' in script
    assert 'desktop.writeConfig("MultiScreenMode", "span")' in script
    assert 'desktop.writeConfig("PropertyOverrides", "{\\"enabled\\":false}")' in script
    assert 'desktop.writeConfig("DisableParallax", true)' in script
    assert script.count("desktop.reloadConfig();") == 1
    assert script.rindex('desktop.writeConfig("WallpaperSource", "/tmp/a.jpg+image")') < script.index("desktop.reloadConfig();")
    assert "UntrustedKey" not in script


def test_wallpaper_readback_requires_the_exact_staged_source_and_id():
    parsed = pyext.parse_wallpaper_readback("""wallpaperPlugin: org.dcentwallpapers.plasma
WallpaperSource: /tmp/right.jpg+image
WallpaperType: image
WallpaperWorkShopId: 1234
MediaPath: /tmp/right.jpg
""")
    assert pyext.wallpaper_readback_matches(parsed, {
        "WallpaperSource": "/tmp/right.jpg+image",
        "WallpaperType": "image",
        "WallpaperWorkShopId": "1234",
        "MediaPath": "/tmp/right.jpg",
    }) is True
    assert pyext.wallpaper_readback_matches(parsed, {
        "WallpaperSource": "/tmp/other.jpg+image",
        "WallpaperWorkShopId": "9999",
    }) is False


def test_login_commands_use_fixed_programs_and_switch_provider_last(tmp_path):
    prepared = tmp_path / "login-preview.jpg"
    destination = Path("/var/lib/plasmalogin/wallpapers/dcent-login-test.jpg")
    commands = pyext.build_login_wallpaper_commands(prepared, destination)

    assert len(commands) == 4
    assert all(command[0] == "/usr/bin/pkexec" for command in commands)
    assert all("sh" not in command[1] for command in commands)
    assert commands[1][-2:] == [str(prepared), str(destination)]
    assert commands[2][-1] == f"file://{destination}"
    assert commands[3][-1] == "org.kde.image"
    assert commands[3][-3:-1] == ["--key", "WallpaperPlugin"]


def test_runtime_scene_loader_rechecks_isolated_captsilver_preflight_and_only_queries_cache():
    root = Path(__file__).resolve().parents[1]
    main = (root / "plasma-plugin/contents/ui/main.qml").read_text()
    helper = (root / "tools/scene_preflight.cpp").read_text()

    assert "pyext.preflight_scene(requestedSource, assetsPath)" in main
    assert "function loadSceneAfterPreflight(generation)" in main
    assert "loadSceneAnimatedFallback(generation, true)" in main
    assert "Boolean(cacheOnly)" in main
    assert "import com.github.captsilver.wallpaperEngineKde 1.2" in helper
